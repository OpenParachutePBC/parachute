import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:app/core/services/gemma_model_manager.dart';
import 'package:app/core/services/ollama_cleanup_service.dart';
import 'package:app/core/models/title_generation_models.dart';

/// Unified local LLM service that abstracts platform-specific backends
///
/// Platform backends:
/// - Mobile (Android/iOS): flutter_gemma (MediaPipe on-device)
/// - Desktop (macOS/Linux/Windows): Ollama (local server)
///
/// This service provides high-level AI capabilities:
/// - Transcript cleanup (fix errors, add structure)
/// - Title generation (create meaningful titles)
/// - Summary generation (extract key points)
class LocalLlmService {
  final GemmaModelManager _gemmaManager;
  final OllamaCleanupService _ollamaService;
  final Future<GemmaModelType?> Function() _getPreferredGemmaModel;
  final Future<String?> Function() _getOllamaModel;

  LocalLlmService(
    this._gemmaManager,
    this._ollamaService,
    this._getPreferredGemmaModel,
    this._getOllamaModel,
  );

  /// Clean up a voice transcript
  ///
  /// Fixes transcription errors, improves grammar and punctuation,
  /// adds paragraph structure, removes filler words.
  ///
  /// For long transcripts (>1500 words), processes in chunks to avoid
  /// token limits while preserving all content.
  ///
  /// [context] helps understand the purpose/setting (e.g., "morning journal", "meeting notes")
  /// to inform structure and formatting decisions, but is NOT added to the output.
  Future<String?> cleanupTranscript(
    String rawTranscript, {
    String? context,
  }) async {
    if (rawTranscript.trim().isEmpty) {
      return null;
    }

    // Check if we need to chunk (roughly 1500 words = ~2000 tokens input)
    final words = rawTranscript.split(RegExp(r'\s+'));
    if (words.length <= 1500) {
      // Short transcript - process directly
      final prompt = _buildCleanupPrompt(rawTranscript, context: context);
      final result = await _generateCompletion(prompt, maxTokens: 4096);
      return _cleanTranscriptOutput(result);
    }

    // Long transcript - process in chunks
    debugPrint('[LocalLlm] Long transcript (${words.length} words), processing in chunks...');
    return await _cleanupInChunks(rawTranscript, context: context);
  }

  /// Process long transcripts in chunks to avoid token limits
  Future<String?> _cleanupInChunks(
    String rawTranscript, {
    String? context,
  }) async {
    // Split into chunks of ~1200 words (leaves room for prompt + output)
    const chunkSize = 1200;
    final sentences = _splitIntoSentences(rawTranscript);
    final chunks = <String>[];
    var currentChunk = StringBuffer();
    var currentWordCount = 0;

    for (final sentence in sentences) {
      final sentenceWords = sentence.split(RegExp(r'\s+')).length;

      if (currentWordCount + sentenceWords > chunkSize && currentChunk.isNotEmpty) {
        // Save current chunk and start new one
        chunks.add(currentChunk.toString().trim());
        currentChunk = StringBuffer();
        currentWordCount = 0;
      }

      currentChunk.write(sentence);
      currentChunk.write(' ');
      currentWordCount += sentenceWords;
    }

    // Don't forget the last chunk
    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.toString().trim());
    }

    debugPrint('[LocalLlm] Split into ${chunks.length} chunks');

    // Process each chunk
    final cleanedChunks = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      debugPrint('[LocalLlm] Processing chunk ${i + 1}/${chunks.length}...');

      final chunkContext = context != null
          ? '$context (part ${i + 1} of ${chunks.length})'
          : 'part ${i + 1} of ${chunks.length}';

      final prompt = _buildCleanupPrompt(chunks[i], context: chunkContext);
      final rawCleaned = await _generateCompletion(prompt, maxTokens: 4096);
      final cleaned = _cleanTranscriptOutput(rawCleaned);

      if (cleaned != null && cleaned.trim().isNotEmpty) {
        cleanedChunks.add(cleaned.trim());
      } else {
        // If cleanup failed, use original chunk to avoid data loss
        debugPrint('[LocalLlm] Chunk ${i + 1} cleanup failed, using original');
        cleanedChunks.add(chunks[i]);
      }
    }

    // Join chunks with paragraph breaks
    return cleanedChunks.join('\n\n');
  }

  /// Split text into sentences for chunking
  List<String> _splitIntoSentences(String text) {
    // Split on sentence-ending punctuation followed by space
    final sentencePattern = RegExp(r'(?<=[.!?])\s+');
    final sentences = text.split(sentencePattern);
    return sentences.where((s) => s.trim().isNotEmpty).toList();
  }

  /// Generate a title for a transcript
  ///
  /// Creates a concise, meaningful title that captures the main topic.
  ///
  /// [context] provides additional information to help generate a more relevant title.
  Future<String?> generateTitle(String transcript, {String? context}) async {
    if (transcript.trim().isEmpty) {
      return null;
    }

    final prompt = _buildTitlePrompt(transcript, context: context);
    // maxTokens is TOTAL (input + output), need ~200 for prompt + transcript + response
    final rawTitle = await _generateCompletion(prompt, maxTokens: 512);

    if (rawTitle == null || rawTitle.trim().isEmpty) {
      return null;
    }

    // Clean up the output (small models often don't follow instructions precisely)
    return _cleanTitleOutput(rawTitle);
  }

  /// Generate a summary of a transcript
  ///
  /// Extracts key points and main ideas in a concise format.
  ///
  /// [context] provides additional information to help focus the summary.
  Future<String?> generateSummary(String transcript, {String? context}) async {
    if (transcript.trim().isEmpty) {
      return null;
    }

    final prompt = _buildSummaryPrompt(transcript, context: context);
    return await _generateCompletion(prompt, maxTokens: 512);
  }

  /// Answer a question using journal context (RAG)
  ///
  /// Uses retrieved journal excerpts as context to answer the user's question.
  /// Returns a concise answer based only on the provided context.
  ///
  /// [question] is the user's query
  /// [journalContext] is the concatenated relevant journal excerpts
  Future<String?> generateAnswer(
    String question, {
    required String journalContext,
  }) async {
    if (question.trim().isEmpty) {
      return null;
    }

    final prompt = _buildAnswerPrompt(question, journalContext);
    return await _generateCompletion(prompt, maxTokens: 512);
  }

  /// Generate a completion using the appropriate backend
  Future<String?> _generateCompletion(
    String prompt, {
    required int maxTokens,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return await _generateWithFlutterGemma(prompt, maxTokens: maxTokens);
    } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      return await _generateWithOllama(prompt);
    }

    throw UnsupportedError(
      'Platform ${Platform.operatingSystem} not supported',
    );
  }

  /// Generate completion using flutter_gemma (mobile)
  Future<String?> _generateWithFlutterGemma(
    String prompt, {
    required int maxTokens,
  }) async {
    try {
      debugPrint('[LocalLlm] Using flutter_gemma (mobile)...');

      // Get the preferred model (default to gemma1b if not set)
      var modelType = await _getPreferredGemmaModel();

      // If no model preference set, try to use gemma1b as default
      if (modelType == null) {
        debugPrint('[LocalLlm] No model preference set, checking for gemma1b...');
        final gemma1bDownloaded = await _gemmaManager.isModelDownloaded(GemmaModelType.gemma1b);
        if (gemma1bDownloaded) {
          modelType = GemmaModelType.gemma1b;
          debugPrint('[LocalLlm] Using gemma1b as default');
        } else {
          throw Exception(
            'No AI model configured.\n\n'
            'Please go to Settings → Local AI and download the Gemma 1B model.',
          );
        }
      }

      // Check if model is actually downloaded
      final isDownloaded = await _gemmaManager.isModelDownloaded(modelType);
      if (!isDownloaded) {
        throw Exception(
          'AI model not downloaded.\n\n'
          'Please go to Settings → Local AI and download the ${modelType.displayName} model.',
        );
      }

      // Get model instance
      final model = await _gemmaManager.getModel(
        maxTokens: maxTokens,
        modelType: modelType,
      );

      // Generate completion
      final result = await _gemmaManager.generateTitle(
        model: model,
        prompt: prompt,
      );

      // Close model
      await model.close();

      debugPrint('[LocalLlm] ✅ Generation complete (flutter_gemma)');
      return result;
    } catch (e) {
      debugPrint('[LocalLlm] ❌ Generation failed (flutter_gemma): $e');
      rethrow;
    }
  }

  /// Generate completion using Ollama (desktop)
  Future<String?> _generateWithOllama(String prompt) async {
    try {
      debugPrint('[LocalLlm] Using Ollama (desktop)...');

      // Get the preferred Ollama model
      final model = await _getOllamaModel();

      // Check if Ollama is available
      if (!await _ollamaService.isAvailable()) {
        throw Exception(
          'Ollama is not running.\n\n'
          'Please install Ollama and start the server.\n'
          'See Settings → Ollama Configuration for instructions.',
        );
      }

      // Use Ollama's generic completion method (we already built the prompt)
      final result = await _ollamaService.generateCompletion(
        prompt,
        model: model,
      );

      debugPrint('[LocalLlm] ✅ Generation complete (Ollama)');
      return result;
    } catch (e) {
      debugPrint('[LocalLlm] ❌ Generation failed (Ollama): $e');
      rethrow;
    }
  }

  /// Build prompt for transcript cleanup
  String _buildCleanupPrompt(String transcript, {String? context}) {
    final contextSection = context != null && context.trim().isNotEmpty
        ? '''
Context/Purpose: $context
(Use this context to inform how you structure and format the transcript, but DO NOT include this context information in the cleaned output.)

'''
        : '';

    return '''Clean up this voice-to-text transcript. The input comes from automatic speech recognition, so it may contain transcription errors where similar-sounding words were incorrectly captured.

${contextSection}Your task:
1. Fix obvious transcription errors where context suggests a different word was meant
   - Only correct when you're confident based on context
   - Similar-sounding words (e.g., "their" vs "there", "to" vs "too")
   - Common speech-to-text mistakes
   - Be conservative - when uncertain, keep the original word

2. Improve readability and structure:
   - Fix grammar, punctuation, and spacing
   - Remove filler words (um, uh, like, you know, hmm, etc.)
   - IMPORTANT: Break the transcript into clear paragraphs
     * Add a paragraph break whenever the speaker shifts to a new topic or thought
     * Add a paragraph break after 3-5 sentences if discussing the same topic
     * Use blank lines between paragraphs for clear visual separation
     * For journal entries or stream-of-consciousness content, be generous with paragraph breaks
   - Make sentences flow naturally within each paragraph
   - Keep the same meaning and content
   - Use the context information (if provided) to inform structure choices

3. Maintain authenticity and PRESERVE ALL CONTENT:
   - Preserve the speaker's natural, conversational tone
   - Keep the original voice and style
   - DO NOT add new information or interpretations
   - DO NOT summarize or shorten the content
   - DO NOT skip or omit ANY sentences or ideas
   - DO NOT over-formalize casual speech
   - DO NOT include the context information in the output
   - The cleaned version should contain ALL the same information as the original
   - If in doubt, include more rather than less

CRITICAL REQUIREMENTS:
1. Output ONLY the cleaned transcript text itself
2. Do not include any preamble like "Here's the cleaned version" or explanations
3. Start directly with the first word of the cleaned transcript
4. The output MUST contain all the content from the original - do not cut anything off

Original transcript:
$transcript''';
  }

  /// Build prompt for title generation
  String _buildTitlePrompt(String transcript, {String? context}) {
    // Truncate transcript for title generation - only need beginning to understand topic
    // This keeps token count low for mobile LLMs
    final truncatedTranscript = _truncateForTitle(transcript);

    // Very direct prompt - small models follow simple instructions better
    // Emphasize: output ONLY the title, nothing else
    return '''Create a 3-6 word title for this text. Output ONLY the title, no explanation.

Text: "$truncatedTranscript"

Title:''';
  }

  /// Clean up transcript output from LLM (remove preamble/postamble)
  ///
  /// Small models often add things like "Here's the cleaned version:" despite
  /// instructions not to. This strips common preamble patterns.
  String? _cleanTranscriptOutput(String? rawOutput) {
    if (rawOutput == null || rawOutput.trim().isEmpty) {
      return null;
    }

    var cleaned = rawOutput.trim();

    // Common preamble patterns that small models add despite instructions
    final preamblePatterns = [
      // "Here's the cleaned/corrected/improved transcript/version:"
      RegExp(
        r"^here'?s?\s+(the\s+)?(cleaned|corrected|improved|fixed|revised|updated)?\s*(transcript|version|text)?[:\s]*",
        caseSensitive: false,
      ),
      // "The cleaned transcript is:"
      RegExp(
        r'^the\s+(cleaned|corrected|improved)\s+(transcript|version|text)\s*(is)?[:\s]*',
        caseSensitive: false,
      ),
      // "Cleaned transcript:" or "Cleaned version:"
      RegExp(
        r'^(cleaned|corrected|improved|fixed)\s+(transcript|version|text)?[:\s]*',
        caseSensitive: false,
      ),
      // "Sure, here's..." or "Of course, here's..."
      RegExp(
        r"^(sure|of course|certainly|okay)[,.]?\s*(here'?s?)?[:\s]*",
        caseSensitive: false,
      ),
      // "I've cleaned up the transcript:"
      RegExp(
        r"^i'?ve\s+(cleaned|corrected|improved|fixed).*?[:\s]*",
        caseSensitive: false,
      ),
    ];

    // Try each pattern
    for (final pattern in preamblePatterns) {
      final match = pattern.firstMatch(cleaned);
      if (match != null) {
        cleaned = cleaned.substring(match.end).trim();
        debugPrint('[LocalLlm] Stripped preamble from cleanup output');
        break;
      }
    }

    // Also check for common postamble patterns
    final postamblePatterns = [
      // "Let me know if you need anything else"
      RegExp(
        r'\n+let me know if.*$',
        caseSensitive: false,
      ),
      // "I hope this helps"
      RegExp(
        r'\n+i hope this helps.*$',
        caseSensitive: false,
      ),
      // "Is there anything else..."
      RegExp(
        r'\n+is there anything else.*$',
        caseSensitive: false,
      ),
    ];

    for (final pattern in postamblePatterns) {
      cleaned = cleaned.replaceFirst(pattern, '').trim();
    }

    return cleaned.isEmpty ? null : cleaned;
  }

  /// Clean up title output from LLM (extract just the title)
  String _cleanTitleOutput(String rawOutput) {
    var title = rawOutput.trim();

    // Remove common preamble patterns that LLMs add
    final preamblePatterns = [
      RegExp(r"^here'?s?\s+(a\s+)?(few\s+)?(options?|suggestions?|titles?).*?:\s*", caseSensitive: false),
      RegExp(r'^(the\s+)?title\s*(is|could be|would be)?:?\s*', caseSensitive: false),
      RegExp(r'^(a\s+)?(short\s+)?title\s*:?\s*', caseSensitive: false),
      RegExp(r'^(i\s+)?(would\s+)?(suggest|recommend).*?:\s*', caseSensitive: false),
      RegExp(r'^(based on|for this).*?:\s*', caseSensitive: false),
    ];

    for (final pattern in preamblePatterns) {
      title = title.replaceFirst(pattern, '');
    }
    title = title.trim();

    // Remove markdown formatting (bold, italic)
    title = title.replaceAll(RegExp(r'\*+'), '');
    title = title.replaceAll(RegExp(r'_+'), '');

    // Remove quotes if wrapped
    if ((title.startsWith('"') && title.endsWith('"')) ||
        (title.startsWith("'") && title.endsWith("'"))) {
      title = title.substring(1, title.length - 1);
    }

    // If it's multiple lines, take the first non-empty line that looks like a title
    if (title.contains('\n')) {
      final lines = title.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      for (final line in lines) {
        // Skip lines that look like list markers or explanations
        if (line.startsWith(RegExp(r'^\d+[.):]\s*'))) {
          // This is a numbered list item - extract just the title part
          final extracted = line.replaceFirst(RegExp(r'^\d+[.):]\s*'), '').trim();
          if (extracted.isNotEmpty && extracted.length <= 80) {
            title = extracted;
            break;
          }
        } else if (line.length <= 80 && !line.contains(':')) {
          // This looks like a clean title
          title = line;
          break;
        }
      }
    }

    // If it's too long (model wrote a summary), truncate to first sentence
    if (title.length > 80) {
      final firstSentence = title.split(RegExp(r'[.!?]')).first.trim();
      if (firstSentence.length > 10 && firstSentence.length <= 80) {
        title = firstSentence;
      } else {
        // Just take first 60 chars and add ellipsis
        title = '${title.substring(0, 60).trim()}...';
      }
    }

    // Remove trailing punctuation
    title = title.replaceAll(RegExp(r'[.!?]+$'), '');

    // Remove leading/trailing quotes again after all processing
    title = title.trim();
    if ((title.startsWith('"') && title.endsWith('"')) ||
        (title.startsWith("'") && title.endsWith("'"))) {
      title = title.substring(1, title.length - 1);
    }

    return title.trim();
  }

  /// Truncate transcript for title generation (keep first ~150 words)
  String _truncateForTitle(String transcript) {
    final words = transcript.split(RegExp(r'\s+'));
    if (words.length <= 150) return transcript;
    return '${words.take(150).join(' ')}...';
  }

  /// Build prompt for summary generation
  String _buildSummaryPrompt(String transcript, {String? context}) {
    // Determine perspective based on context
    String perspectiveGuidance = '';
    if (context != null && context.trim().isNotEmpty) {
      final contextLower = context.toLowerCase();
      if (contextLower.contains('journal')) {
        perspectiveGuidance = '''
- Write in second person (e.g., "You reflected on...", "You discussed...")
- Match the personal, reflective tone of a journal entry
''';
      } else if (contextLower.contains('meeting') ||
          contextLower.contains('notes')) {
        perspectiveGuidance = '''
- Write objectively in third person or use passive voice
- Focus on decisions, action items, and key points
''';
      } else {
        perspectiveGuidance = '''
- Use second person (e.g., "You mentioned...", "You explored...")
- Keep it personal and direct
''';
      }
    } else {
      perspectiveGuidance = '''
- Use second person (e.g., "You mentioned...", "You explored...")
- Keep it personal and direct
''';
    }

    final contextSection = context != null && context.trim().isNotEmpty
        ? '''
Context/Purpose: $context
(Use this context to focus the summary on what's most relevant and inform the writing style.)

'''
        : '';

    return '''Generate a concise summary of this voice note transcript. Extract the key points and main ideas.

${contextSection}Guidelines:
- 2-4 sentences maximum
- Focus on main ideas and key takeaways
- Use clear, natural language
- Preserve important details and context
- Don't add interpretations or opinions
- Don't use phrases like "This transcript discusses..." or "The speaker talks about..."
$perspectiveGuidance- If context is provided, use it to emphasize the most relevant aspects

Output ONLY the summary, nothing else.

Transcript:
$transcript

Summary:''';
  }

  /// Build prompt for answering questions about journals (RAG)
  String _buildAnswerPrompt(String question, String journalContext) {
    return '''You are answering a question about the user's personal journal entries.

IMPORTANT: Use ONLY the journal excerpts provided below to answer. If the answer is not clearly in the excerpts, say "I couldn't find information about that in your recent journals."

## Journal Excerpts
$journalContext

## Question
$question

## Answer
Provide a concise, helpful answer based on the journal excerpts above. Reference specific dates when relevant. Use second person ("you wrote", "you mentioned").

Answer:''';
  }
}
