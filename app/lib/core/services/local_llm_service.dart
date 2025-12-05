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
  /// [context] helps understand the purpose/setting (e.g., "morning journal", "meeting notes")
  /// to inform structure and formatting decisions, but is NOT added to the output.
  Future<String?> cleanupTranscript(
    String rawTranscript, {
    String? context,
  }) async {
    if (rawTranscript.trim().isEmpty) {
      return null;
    }

    final prompt = _buildCleanupPrompt(rawTranscript, context: context);
    return await _generateCompletion(prompt, maxTokens: 2048);
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

      // Get the preferred model
      final modelType = await _getPreferredGemmaModel();
      if (modelType == null) {
        throw Exception(
          'No Gemma model configured. Please download and select a model in Settings.',
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

3. Maintain authenticity:
   - Preserve the speaker's natural, conversational tone
   - Keep the original voice and style
   - DO NOT add new information or interpretations
   - DO NOT summarize or shorten content
   - DO NOT over-formalize casual speech
   - DO NOT include the context information in the output

CRITICAL: Output ONLY the cleaned transcript text itself. Do not include any preamble like "Here's the cleaned version" or "Cleaned transcript:" or any explanations. Start directly with the first word of the cleaned transcript.

Original transcript:
$transcript''';
  }

  /// Build prompt for title generation
  String _buildTitlePrompt(String transcript, {String? context}) {
    // Truncate transcript for title generation - only need beginning to understand topic
    // This keeps token count low for mobile LLMs
    final truncatedTranscript = _truncateForTitle(transcript);

    final contextHint = context != null && context.trim().isNotEmpty
        ? ' about $context'
        : '';

    // Very simple prompt - small models follow simple instructions better
    return '''Write a short title (5-8 words) for this voice note$contextHint:

"$truncatedTranscript"

Title:''';
  }

  /// Clean up title output from LLM (extract just the title)
  String _cleanTitleOutput(String rawOutput) {
    var title = rawOutput.trim();

    // Remove markdown formatting (bold, italic)
    title = title.replaceAll(RegExp(r'\*+'), '');
    title = title.replaceAll(RegExp(r'_+'), '');

    // Remove quotes if wrapped
    if ((title.startsWith('"') && title.endsWith('"')) ||
        (title.startsWith("'") && title.endsWith("'"))) {
      title = title.substring(1, title.length - 1);
    }

    // If it's multiple lines, take just the first line
    if (title.contains('\n')) {
      title = title.split('\n').first.trim();
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
}
