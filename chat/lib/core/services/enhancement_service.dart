import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:parachute_chat/core/services/local_llm_service.dart';
import 'package:parachute_chat/features/recorder/services/storage_service.dart';

/// Progress callback for enhancement operations
/// [status] - Human-readable status message
/// [progress] - Progress from 0.0 to 1.0 (null for indeterminate)
typedef EnhancementProgressCallback = void Function(String status, double? progress);

/// Result of an enhancement operation
class EnhancementResult {
  final String? cleanedContent;
  final String? generatedTitle;
  final bool usedRemote;
  final String? error;

  EnhancementResult({
    this.cleanedContent,
    this.generatedTitle,
    this.usedRemote = false,
    this.error,
  });

  bool get isSuccess => cleanedContent != null && error == null;
}

/// Service that handles AI enhancement of transcripts
///
/// Routes to either remote agent or local LLM based on settings.
/// Provides progress callbacks for UI feedback.
class EnhancementService {
  final LocalLlmService _localLlmService;
  final StorageService _storageService;
  final String Function() _getAgentServerUrl;
  final http.Client _client;

  EnhancementService({
    required LocalLlmService localLlmService,
    required StorageService storageService,
    required String Function() getAgentServerUrl,
    http.Client? httpClient,
  })  : _localLlmService = localLlmService,
        _storageService = storageService,
        _getAgentServerUrl = getAgentServerUrl,
        _client = httpClient ?? http.Client();

  /// Check if remote agent server is available
  Future<bool> isRemoteAvailable() async {
    try {
      final baseUrl = _getAgentServerUrl();
      if (baseUrl.isEmpty) return false;

      final response = await _client
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 3));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[EnhancementService] Remote not available: $e');
      return false;
    }
  }

  /// Enhance a transcript (cleanup + title generation)
  ///
  /// Uses remote agent or local LLM based on settings.
  /// [onProgress] receives progress updates for UI feedback.
  Future<EnhancementResult> enhance(
    String transcript, {
    String? context,
    EnhancementProgressCallback? onProgress,
  }) async {
    if (transcript.trim().isEmpty) {
      return EnhancementResult(error: 'Empty transcript');
    }

    final mode = await _storageService.getAiEnhancementMode();
    debugPrint('[EnhancementService] Enhancement mode: ${mode.name}');

    switch (mode) {
      case AiEnhancementMode.local:
        return await _enhanceWithLocal(transcript, context: context, onProgress: onProgress);

      case AiEnhancementMode.remote:
        final remoteAvailable = await isRemoteAvailable();
        if (!remoteAvailable) {
          return EnhancementResult(error: 'Remote agent not available');
        }
        return await _enhanceWithRemote(transcript, context: context, onProgress: onProgress);

      case AiEnhancementMode.remoteWithFallback:
        onProgress?.call('Checking remote agent...', null);
        final remoteAvailable = await isRemoteAvailable();
        if (remoteAvailable) {
          debugPrint('[EnhancementService] Using remote agent');
          return await _enhanceWithRemote(transcript, context: context, onProgress: onProgress);
        } else {
          debugPrint('[EnhancementService] Remote unavailable, falling back to local');
          onProgress?.call('Remote unavailable, using local AI...', null);
          return await _enhanceWithLocal(transcript, context: context, onProgress: onProgress);
        }
    }
  }

  /// Enhance using remote agent via streaming chat
  Future<EnhancementResult> _enhanceWithRemote(
    String transcript, {
    String? context,
    EnhancementProgressCallback? onProgress,
  }) async {
    final baseUrl = _getAgentServerUrl();

    try {
      // Step 1: Clean up transcript
      onProgress?.call('Cleaning up transcript...', 0.1);
      final cleanedContent = await _remoteCleanup(baseUrl, transcript, context: context, onProgress: onProgress);

      if (cleanedContent == null || cleanedContent.isEmpty) {
        return EnhancementResult(error: 'Remote cleanup failed');
      }

      // Step 2: Generate title
      onProgress?.call('Generating title...', 0.8);
      final title = await _remoteGenerateTitle(baseUrl, cleanedContent, context: context);

      onProgress?.call('Enhancement complete', 1.0);

      return EnhancementResult(
        cleanedContent: cleanedContent,
        generatedTitle: title,
        usedRemote: true,
      );
    } catch (e) {
      debugPrint('[EnhancementService] Remote enhancement failed: $e');
      return EnhancementResult(error: 'Remote enhancement failed: $e');
    }
  }

  /// Remote transcript cleanup via streaming
  Future<String?> _remoteCleanup(
    String baseUrl,
    String transcript, {
    String? context,
    EnhancementProgressCallback? onProgress,
  }) async {
    final prompt = '''Clean up this voice transcript. Fix transcription errors, improve grammar and punctuation, remove filler words (um, uh, like), and break into clear paragraphs.

IMPORTANT: Output ONLY the cleaned transcript. No preamble, no explanations, just the cleaned text.

${context != null ? 'Context: $context\n\n' : ''}Transcript:
$transcript''';

    try {
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/api/chat/stream'),
      );

      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'message': prompt,
        'sessionId': 'enhancement-${DateTime.now().millisecondsSinceEpoch}',
        // No agent specified - uses default vault agent
      });

      final streamedResponse = await _client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Server returned ${streamedResponse.statusCode}');
      }

      final buffer = StringBuffer();
      var charCount = 0;
      final estimatedChars = transcript.length; // Rough estimate

      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        // Parse SSE events
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data: ')) {
            try {
              final data = jsonDecode(line.substring(6)) as Map<String, dynamic>;
              final type = data['type'] as String?;

              if (type == 'text') {
                final content = data['content'] as String? ?? '';
                buffer.write(content);
                charCount += content.length;

                // Update progress based on characters received
                final progress = (charCount / estimatedChars).clamp(0.1, 0.75);
                onProgress?.call('Cleaning up... ${(progress * 100).toInt()}%', progress);
              } else if (type == 'error') {
                throw Exception(data['error'] ?? 'Unknown error');
              }
            } catch (e) {
              // Ignore parse errors for non-JSON lines
            }
          }
        }
      }

      final result = buffer.toString().trim();
      return result.isEmpty ? null : _stripPreamble(result);
    } catch (e) {
      debugPrint('[EnhancementService] Remote cleanup error: $e');
      rethrow;
    }
  }

  /// Remote title generation (non-streaming for simplicity)
  Future<String?> _remoteGenerateTitle(
    String baseUrl,
    String content, {
    String? context,
  }) async {
    final prompt = '''Create a concise 3-6 word title for this text. Output ONLY the title, nothing else.

Text: "${content.length > 500 ? '${content.substring(0, 500)}...' : content}"

Title:''';

    try {
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/api/chat/stream'),
      );

      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'message': prompt,
        'sessionId': 'title-${DateTime.now().millisecondsSinceEpoch}',
      });

      final streamedResponse = await _client.send(request);

      if (streamedResponse.statusCode != 200) {
        return null;
      }

      final buffer = StringBuffer();

      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data: ')) {
            try {
              final data = jsonDecode(line.substring(6)) as Map<String, dynamic>;
              final type = data['type'] as String?;

              if (type == 'text') {
                buffer.write(data['content'] ?? '');
              }
            } catch (e) {
              // Ignore parse errors
            }
          }
        }
      }

      final rawTitle = buffer.toString().trim();
      return _cleanTitle(rawTitle);
    } catch (e) {
      debugPrint('[EnhancementService] Remote title generation error: $e');
      return null;
    }
  }

  /// Enhance using local LLM (Gemma/Ollama)
  Future<EnhancementResult> _enhanceWithLocal(
    String transcript, {
    String? context,
    EnhancementProgressCallback? onProgress,
  }) async {
    try {
      // Step 1: Clean up transcript
      onProgress?.call('Cleaning up transcript (local AI)...', null);
      final cleanedContent = await _localLlmService.cleanupTranscript(
        transcript,
        context: context,
      );

      if (cleanedContent == null || cleanedContent.isEmpty) {
        return EnhancementResult(error: 'Local cleanup failed');
      }

      // Step 2: Generate title
      onProgress?.call('Generating title (local AI)...', null);
      final title = await _localLlmService.generateTitle(
        cleanedContent,
        context: context,
      );

      onProgress?.call('Enhancement complete', 1.0);

      return EnhancementResult(
        cleanedContent: cleanedContent,
        generatedTitle: title,
        usedRemote: false,
      );
    } catch (e) {
      debugPrint('[EnhancementService] Local enhancement failed: $e');
      return EnhancementResult(error: 'Local enhancement failed: $e');
    }
  }

  /// Strip common preamble from LLM output
  String _stripPreamble(String text) {
    var cleaned = text.trim();

    final patterns = [
      RegExp(r"^here'?s?\s+(the\s+)?(cleaned|corrected|improved).*?:\s*", caseSensitive: false),
      RegExp(r'^(sure|of course|certainly).*?:\s*', caseSensitive: false),
      RegExp(r"^i'?ve\s+(cleaned|corrected).*?:\s*", caseSensitive: false),
    ];

    for (final pattern in patterns) {
      cleaned = cleaned.replaceFirst(pattern, '').trim();
    }

    return cleaned;
  }

  /// Clean up title output
  String? _cleanTitle(String? rawTitle) {
    if (rawTitle == null || rawTitle.trim().isEmpty) return null;

    var title = rawTitle.trim();

    // Remove quotes
    if ((title.startsWith('"') && title.endsWith('"')) ||
        (title.startsWith("'") && title.endsWith("'"))) {
      title = title.substring(1, title.length - 1);
    }

    // Take first line if multiple
    if (title.contains('\n')) {
      title = title.split('\n').first.trim();
    }

    // Limit length
    if (title.length > 60) {
      title = '${title.substring(0, 57)}...';
    }

    return title.isEmpty ? null : title;
  }

  void dispose() {
    _client.close();
  }
}
