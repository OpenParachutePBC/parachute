import 'package:flutter/foundation.dart';
import 'package:ollama_dart/ollama_dart.dart';

/// Service for cleaning up voice transcripts using Ollama (desktop)
///
/// This service uses Ollama's REST API to run local LLM inference
/// on desktop platforms (macOS, Linux, Windows) where flutter_gemma
/// is not yet supported.
///
/// Requires:
/// - Ollama installed: brew install ollama (macOS)
/// - Ollama server running: ollama serve
/// - Model downloaded: ollama pull gemma2:2b
class OllamaCleanupService {
  final OllamaClient _client;
  final String _defaultModel;

  OllamaCleanupService({
    OllamaClient? client,
    String defaultModel = 'gemma2:2b',
  }) : _client = client ?? OllamaClient(),
       _defaultModel = defaultModel;

  /// Check if Ollama is available and running
  Future<bool> isAvailable() async {
    try {
      await _client.listModels();
      return true;
    } catch (e) {
      debugPrint('[OllamaCleanup] Ollama not available: $e');
      return false;
    }
  }

  /// Get list of available models
  Future<List<String>> getAvailableModels() async {
    try {
      final response = await _client.listModels();
      return response.models
              ?.map((model) => model.model ?? '')
              .where((name) => name.isNotEmpty)
              .toList() ??
          [];
    } catch (e) {
      debugPrint('[OllamaCleanup] Failed to list models: $e');
      return [];
    }
  }

  /// Clean up a transcript using Ollama
  ///
  /// Returns cleaned transcript or null if cleanup fails
  Future<String?> cleanupTranscript(
    String rawTranscript, {
    String? model,
  }) async {
    if (rawTranscript.trim().isEmpty) {
      debugPrint('[OllamaCleanup] Empty transcript, skipping cleanup');
      return null;
    }

    try {
      debugPrint('[OllamaCleanup] Starting cleanup...');

      // Check if Ollama is available
      if (!await isAvailable()) {
        throw Exception(
          'Ollama is not running.\n\n'
          'Please install Ollama:\n'
          '  macOS: brew install ollama\n'
          '  Linux/Windows: https://ollama.com/download\n\n'
          'Then start the server:\n'
          '  ollama serve\n\n'
          'And download a model:\n'
          '  ollama pull gemma2:2b',
        );
      }

      final modelToUse = model ?? _defaultModel;

      // Check if the model is downloaded
      final availableModels = await getAvailableModels();
      if (!availableModels.contains(modelToUse)) {
        throw Exception(
          'Model "$modelToUse" not found.\n\n'
          'Please download it first:\n'
          '  ollama pull $modelToUse\n\n'
          'Available models: ${availableModels.join(", ")}',
        );
      }

      // Create prompt for cleanup
      final prompt = _buildCleanupPrompt(rawTranscript);

      debugPrint(
        '[OllamaCleanup] Generating completion with model: $modelToUse',
      );

      // Generate completion
      final response = await _client.generateCompletion(
        request: GenerateCompletionRequest(
          model: modelToUse,
          prompt: prompt,
          stream: false,
          options: RequestOptions(
            temperature: 0.3,
            topK: 40,
            topP: 0.9,
            numPredict: 2048,
          ),
        ),
      );

      final cleanedTranscript = response.response?.trim();

      if (cleanedTranscript == null || cleanedTranscript.isEmpty) {
        debugPrint('[OllamaCleanup] Empty response from Ollama');
        return null;
      }

      debugPrint('[OllamaCleanup] ✅ Cleanup complete');
      return cleanedTranscript;
    } catch (e) {
      debugPrint('[OllamaCleanup] ❌ Cleanup failed: $e');
      rethrow;
    }
  }

  /// Build the cleanup prompt
  String _buildCleanupPrompt(String transcript) {
    return '''Clean up this voice-to-text transcript. The input comes from automatic speech recognition, so it may contain transcription errors where similar-sounding words were incorrectly captured.

Your task:
1. Fix obvious transcription errors where context suggests a different word was meant
   - Only correct when you're confident based on context
   - Similar-sounding words (e.g., "their" vs "there", "to" vs "too")
   - Common speech-to-text mistakes
   - Be conservative - when uncertain, keep the original word

2. Improve readability and structure:
   - Fix grammar, punctuation, and spacing
   - Remove filler words (um, uh, like, you know, etc.)
   - Add paragraph breaks to organize distinct thoughts or topic shifts
   - Make sentences flow naturally
   - Keep the same meaning and content

3. Maintain authenticity:
   - Preserve the speaker's natural, conversational tone
   - Keep the original voice and style
   - DO NOT add new information or interpretations
   - DO NOT summarize or shorten content
   - DO NOT over-formalize casual speech

CRITICAL: Output ONLY the cleaned transcript text itself. Do not include any preamble like "Here's the cleaned version" or "Cleaned transcript:" or any explanations. Start directly with the first word of the cleaned transcript.

Original transcript:
$transcript''';
  }

  /// Generate completion with a raw prompt (for use by LocalLlmService)
  ///
  /// This is a lower-level method that takes a complete prompt and generates a completion.
  /// Use this when you've already built the prompt and just need Ollama to process it.
  Future<String?> generateCompletion(String prompt, {String? model}) async {
    try {
      debugPrint('[OllamaCleanup] Generating completion...');

      // Check if Ollama is available
      if (!await isAvailable()) {
        throw Exception(
          'Ollama is not running.\n\n'
          'Please install Ollama and start the server.\n'
          'See Settings → Ollama Configuration for instructions.',
        );
      }

      final modelToUse = model ?? _defaultModel;

      // Check if the model is downloaded
      final availableModels = await getAvailableModels();
      if (!availableModels.contains(modelToUse)) {
        throw Exception(
          'Model "$modelToUse" not found.\n\n'
          'Please download it first:\n'
          '  ollama pull $modelToUse\n\n'
          'Available models: ${availableModels.join(", ")}',
        );
      }

      debugPrint('[OllamaCleanup] Using model: $modelToUse');

      // Generate completion
      final response = await _client.generateCompletion(
        request: GenerateCompletionRequest(
          model: modelToUse,
          prompt: prompt,
          stream: false,
          options: RequestOptions(
            temperature: 0.3,
            topK: 40,
            topP: 0.9,
            numPredict: 2048,
          ),
        ),
      );

      final result = response.response?.trim();

      if (result == null || result.isEmpty) {
        debugPrint('[OllamaCleanup] Empty response from Ollama');
        return null;
      }

      debugPrint('[OllamaCleanup] ✅ Generation complete');
      return result;
    } catch (e) {
      debugPrint('[OllamaCleanup] ❌ Generation failed: $e');
      rethrow;
    }
  }

  /// Dispose resources
  void dispose() {
    _client.endSession();
  }
}
