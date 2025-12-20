import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:app/core/models/title_generation_models.dart';
import 'package:app/core/services/gemma_model_manager.dart';

/// Service for generating semantic titles from transcripts
///
/// Supports both Gemini API (cloud) and local Gemma models (on-device).
/// Falls back to simple extraction (first 6 words) if both fail or are unconfigured.
class TitleGenerationService {
  final Future<String?> Function() _getGeminiApiKey;
  final Future<TitleModelMode> Function() _getTitleMode;
  final Future<GemmaModelType?> Function() _getPreferredGemmaModel;
  final GemmaModelManager _gemmaManager;

  TitleGenerationService(
    this._getGeminiApiKey,
    this._getTitleMode,
    this._getPreferredGemmaModel,
    this._gemmaManager,
  );

  /// Generate a concise title from a transcript
  ///
  /// Attempts to use the configured mode (API or Local).
  /// Falls back to simple extraction (first 6 words) if generation fails.
  Future<String?> generateTitle(
    String transcript, {
    dynamic preferredModel,
  }) async {
    if (transcript.trim().isEmpty) {
      debugPrint('[TitleGen] Empty transcript, returning default');
      return 'Voice Note';
    }

    try {
      // Get title generation mode
      final mode = await _getTitleMode();
      debugPrint('[TitleGen] Title generation mode: ${mode.name}');

      // If disabled, skip AI generation and use fallback
      if (mode == TitleModelMode.disabled) {
        debugPrint('[TitleGen] Title generation disabled, using fallback');
        final fallbackTitle = _generateFallbackTitle(transcript);
        debugPrint('[TitleGen] Using fallback title: "$fallbackTitle"');
        return fallbackTitle;
      }

      if (mode == TitleModelMode.api) {
        // Try Gemini API
        final apiKey = await _getGeminiApiKey();
        if (apiKey != null && apiKey.isNotEmpty) {
          debugPrint('[TitleGen] Attempting Gemini API title generation...');
          final geminiTitle = await _generateWithGeminiApi(transcript, apiKey);
          if (geminiTitle != null && geminiTitle.isNotEmpty) {
            debugPrint(
              '[TitleGen] ✅ Gemini API generated title: "$geminiTitle"',
            );
            return geminiTitle;
          } else {
            debugPrint('[TitleGen] ⚠️ Gemini API returned empty/null title');
          }
        } else {
          debugPrint('[TitleGen] No Gemini API key configured');
        }
      } else if (mode == TitleModelMode.local) {
        // Try Local Gemma
        final modelType = await _getPreferredGemmaModel();
        if (modelType != null) {
          debugPrint(
            '[TitleGen] Attempting local Gemma title generation with ${modelType.modelName}...',
          );
          final gemmaTitle = await _generateWithGemmaLocal(
            transcript,
            modelType,
          );
          if (gemmaTitle != null && gemmaTitle.isNotEmpty) {
            // Check if the title contains special tokens (indicates corrupt model output)
            if (_containsSpecialTokens(gemmaTitle)) {
              debugPrint(
                '[TitleGen] ⚠️ Local Gemma output contains special tokens (corrupt): "$gemmaTitle"',
              );
              debugPrint(
                '[TitleGen] This indicates a problem with the .task model file',
              );
            } else {
              debugPrint(
                '[TitleGen] ✅ Local Gemma generated title: "$gemmaTitle"',
              );
              return gemmaTitle;
            }
          } else {
            debugPrint('[TitleGen] ⚠️ Local Gemma returned empty/null title');
          }
        } else {
          debugPrint('[TitleGen] No local Gemma model configured');
        }
      }
    } catch (e) {
      debugPrint('[TitleGen] ❌ Title generation failed: $e');
      // Fall through to fallback
    }

    // Fallback to simple extraction
    final fallbackTitle = _generateFallbackTitle(transcript);
    debugPrint('[TitleGen] Using fallback title: "$fallbackTitle"');
    return fallbackTitle;
  }

  /// Generate title using Gemini API
  Future<String?> _generateWithGeminiApi(
    String transcript,
    String apiKey,
  ) async {
    // Truncate very long transcripts (keep first ~500 chars)
    final truncated = transcript.length > 500
        ? '${transcript.substring(0, 500)}...'
        : transcript;

    debugPrint(
      '[TitleGen] Transcript length: ${transcript.length}, truncated: ${truncated.length}',
    );

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=$apiKey',
    );

    final body = {
      'contents': [
        {
          'parts': [
            {
              'text':
                  '''Generate a concise 5-8 word title for this voice recording transcript. Only return the title text, no quotes or extra punctuation.

Transcript: "$truncated"

Title:''',
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.3,
        'maxOutputTokens': 20,
        'topP': 0.8,
      },
    };

    debugPrint('[TitleGen] Sending request to Gemini API...');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('[TitleGen] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        debugPrint(
          '[TitleGen] Response body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
        );

        final data = json.decode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String?;
            debugPrint('[TitleGen] Raw Gemini response: "$text"');
            if (text != null) {
              final cleaned = _cleanGeneratedTitle(text);
              debugPrint('[TitleGen] Cleaned title: "$cleaned"');
              return cleaned;
            }
          }
        }
        debugPrint('[TitleGen] ⚠️ No candidates in response');
      } else {
        debugPrint('[TitleGen] ❌ Gemini API error: ${response.statusCode}');
        debugPrint('[TitleGen] Error body: ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('[TitleGen] ❌ Gemini API request failed: $e');
      debugPrint('[TitleGen] Stack trace: $stackTrace');
    }

    return null;
  }

  /// Generate title using local Gemma model
  Future<String?> _generateWithGemmaLocal(
    String transcript,
    GemmaModelType modelType,
  ) async {
    try {
      // Truncate very long transcripts (keep first ~500 chars)
      final truncated = transcript.length > 500
          ? '${transcript.substring(0, 500)}...'
          : transcript;

      debugPrint(
        '[TitleGen] Transcript length: ${transcript.length}, truncated: ${truncated.length}',
      );

      // Create model instance (load the preferred model if not active)
      // Note: maxTokens is TOTAL tokens (input + output), not just output
      // The prompt is ~60 tokens, so we need at least 60 + 20 = 80 total
      final model = await _gemmaManager.getModel(
        maxTokens: 128, // Increased to accommodate prompt + response
        modelType: modelType,
      );

      // Generate title prompt
      final prompt =
          '''Generate a concise 5-8 word title for this voice recording transcript. Only return the title text, no quotes or extra punctuation.

Transcript: "$truncated"

Title:''';

      // Generate title
      final rawTitle = await _gemmaManager.generateTitle(
        model: model,
        prompt: prompt,
      );

      if (rawTitle.isNotEmpty) {
        final cleaned = _cleanGeneratedTitle(rawTitle);
        debugPrint('[TitleGen] Cleaned title: "$cleaned"');
        return cleaned;
      }

      return null;
    } catch (e, stackTrace) {
      debugPrint('[TitleGen] ❌ Local Gemma title generation failed: $e');
      debugPrint('[TitleGen] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Check if text contains special tokens (indicates corrupt model output)
  bool _containsSpecialTokens(String text) {
    // Common special tokens that should never appear in generated text
    final specialTokens = [
      '<pad>',
      '<unk>',
      '<unused',
      '<bos>',
      '<eos>',
      '[multimodal]',
    ];

    return specialTokens.any((token) => text.contains(token));
  }

  /// Clean up generated title text
  String _cleanGeneratedTitle(String rawTitle) {
    // Remove common artifacts
    String cleaned = rawTitle.trim();

    // Remove quotation marks
    cleaned = cleaned.replaceAll(RegExp(r'''^["']|["']$'''), '');

    // Remove "Title:" prefix if present
    cleaned = cleaned.replaceAll(
      RegExp(r'^Title:\s*', caseSensitive: false),
      '',
    );

    // Remove trailing punctuation (except ...)
    if (!cleaned.endsWith('...')) {
      cleaned = cleaned.replaceAll(RegExp(r'[.!?]+$'), '');
    }

    // Limit to reasonable length (max 8 words)
    final words = cleaned.split(RegExp(r'\s+'));
    if (words.length > 8) {
      cleaned = '${words.take(8).join(' ')}...';
    }

    // Fallback if somehow empty
    if (cleaned.isEmpty) {
      return 'Voice Note';
    }

    return cleaned;
  }

  /// Fallback title generation (first 6 words)
  String _generateFallbackTitle(String transcript) {
    final cleaned = transcript.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (cleaned.isEmpty) {
      return 'Voice Note';
    }

    final words = cleaned.split(' ').take(6).toList();
    final title = words.join(' ');

    if (cleaned.split(' ').length > 6) {
      return '$title...';
    }

    return title;
  }

  /// Generate URL-safe slug from title
  String generateSlug(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  /// Generate semantic filename: YYYY-MM-DD_slug
  Future<String> generateFileName(
    String transcript,
    DateTime recordingTime, {
    dynamic preferredModel,
  }) async {
    final title = await generateTitle(
      transcript,
      preferredModel: preferredModel,
    );

    if (title == null || title.isEmpty || title == 'Voice Note') {
      // Fallback to timestamp-based name
      final timestamp = recordingTime
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      return timestamp.replaceAll('T', '_');
    }

    // Generate semantic filename: YYYY-MM-DD_slug
    final dateStr =
        '${recordingTime.year}-${recordingTime.month.toString().padLeft(2, '0')}-${recordingTime.day.toString().padLeft(2, '0')}';
    final slug = generateSlug(title);

    return '${dateStr}_$slug';
  }

  Future<void> dispose() async {
    // Nothing to dispose
  }
}
