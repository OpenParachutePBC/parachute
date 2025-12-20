import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:app/core/services/gemma_model_manager.dart';
import 'package:app/core/services/ollama_cleanup_service.dart';
import 'package:app/core/models/title_generation_models.dart';

/// Service for cleaning up voice transcripts using local AI
///
/// Uses platform-specific backends:
/// - Mobile (Android/iOS): flutter_gemma (on-device MediaPipe)
/// - Desktop (macOS/Linux/Windows): Ollama (local server)
///
/// Takes raw transcripts from voice-to-text and improves:
/// - Grammar and punctuation
/// - Sentence structure and flow
/// - Spacing and formatting
/// - Removes filler words and hesitations
///
/// While preserving:
/// - Original meaning and content
/// - Natural voice and tone
/// - Important details and context
class TranscriptCleanupService {
  final GemmaModelManager _modelManager;
  final OllamaCleanupService _ollamaService;
  final Future<GemmaModelType?> Function() _getPreferredGemmaModel;
  final Future<String?> Function() _getOllamaModel;

  TranscriptCleanupService(
    this._modelManager,
    this._ollamaService,
    this._getPreferredGemmaModel,
    this._getOllamaModel,
  );

  /// Clean up a transcript
  ///
  /// Returns cleaned transcript or null if cleanup fails
  Future<String?> cleanupTranscript(String rawTranscript) async {
    if (rawTranscript.trim().isEmpty) {
      debugPrint('[TranscriptCleanup] Empty transcript, skipping cleanup');
      return null;
    }

    // Use platform-specific backend
    if (Platform.isAndroid || Platform.isIOS) {
      return await _cleanupWithFlutterGemma(rawTranscript);
    } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      return await _cleanupWithOllama(rawTranscript);
    }

    throw UnsupportedError(
      'Platform ${Platform.operatingSystem} not supported',
    );
  }

  /// Clean up using flutter_gemma (mobile)
  Future<String?> _cleanupWithFlutterGemma(String rawTranscript) async {
    try {
      debugPrint('[TranscriptCleanup] Using flutter_gemma (mobile)...');

      // Get the preferred model
      final modelType = await _getPreferredGemmaModel();
      if (modelType == null) {
        debugPrint(
          '[TranscriptCleanup] No Gemma model configured. Please download and select a model in Settings.',
        );
        throw Exception(
          'No Gemma model configured. Please download and select a model in Settings.',
        );
      }

      // Get model instance
      final model = await _modelManager.getModel(
        maxTokens: 2048, // Enough for transcript + cleaned version
        modelType: modelType,
      );

      // Create prompt for cleanup
      final prompt = _buildCleanupPrompt(rawTranscript);

      // Generate cleaned version
      final cleanedTranscript = await _modelManager.generateTitle(
        model: model,
        prompt: prompt,
      );

      // Close model
      await model.close();

      debugPrint('[TranscriptCleanup] ✅ Cleanup complete (flutter_gemma)');
      return cleanedTranscript;
    } catch (e) {
      debugPrint('[TranscriptCleanup] ❌ Cleanup failed (flutter_gemma): $e');
      rethrow;
    }
  }

  /// Clean up using Ollama (desktop)
  Future<String?> _cleanupWithOllama(String rawTranscript) async {
    try {
      debugPrint('[TranscriptCleanup] Using Ollama (desktop)...');

      // Get the preferred Ollama model
      final model = await _getOllamaModel();

      // Use Ollama service
      final cleanedTranscript = await _ollamaService.cleanupTranscript(
        rawTranscript,
        model: model,
      );

      debugPrint('[TranscriptCleanup] ✅ Cleanup complete (Ollama)');
      return cleanedTranscript;
    } catch (e) {
      debugPrint('[TranscriptCleanup] ❌ Cleanup failed (Ollama): $e');
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
}
