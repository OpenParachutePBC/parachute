import 'package:flutter/foundation.dart';
import 'package:ollama_dart/ollama_dart.dart';
import 'package:parachute_daily/core/models/embedding_models.dart';
import 'package:parachute_daily/core/services/embedding/embedding_service.dart';

/// Desktop embedding service using Ollama with EmbeddingGemma
///
/// Uses the same EmbeddingGemma model as mobile for cross-device compatibility.
/// Embeddings are truncated to 256 dimensions using Matryoshka representation.
///
/// Requires Ollama to be installed and running:
/// - Install: brew install ollama (macOS) or https://ollama.com (Linux/Windows)
/// - Start: ollama serve (runs automatically on macOS after install)
///
/// The model is automatically downloaded when needed via the app UI.
class DesktopEmbeddingService implements EmbeddingService {
  final OllamaClient _client;

  DesktopEmbeddingService({OllamaClient? client})
      : _client = client ?? OllamaClient();

  @override
  int get dimensions => DesktopEmbeddingConfig.targetDimensions;

  /// Check if Ollama is running and EmbeddingGemma is available
  @override
  Future<bool> isReady() async {
    try {
      final modelsResponse = await _client.listModels();

      final availableModels = modelsResponse.models
              ?.map((model) => model.model ?? '')
              .where((name) => name.isNotEmpty)
              .toList() ??
          [];

      // Check for embeddinggemma (with or without :latest tag)
      final modelName = DesktopEmbeddingConfig.modelName;
      final isModelAvailable = availableModels.any(
        (model) => model == modelName || model.startsWith('$modelName:'),
      );

      if (isModelAvailable) {
        debugPrint('[DesktopEmbedding] EmbeddingGemma is ready');
      } else {
        debugPrint(
          '[DesktopEmbedding] EmbeddingGemma not found. '
          'Available: ${availableModels.join(", ")}',
        );
      }

      return isModelAvailable;
    } catch (e) {
      debugPrint('[DesktopEmbedding] Ollama not available: $e');
      return false;
    }
  }

  /// Check if Ollama is installed and running
  Future<bool> isOllamaRunning() async {
    try {
      await _client.listModels();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if the model needs to be downloaded
  @override
  Future<bool> needsDownload() async {
    try {
      // First check if Ollama is even running
      if (!await isOllamaRunning()) {
        return true; // Will show appropriate error during download
      }
      return !await isReady();
    } catch (e) {
      debugPrint('[DesktopEmbedding] Error checking download status: $e');
      return true;
    }
  }

  /// Download EmbeddingGemma via Ollama
  ///
  /// Streams real download progress from Ollama's pull API.
  @override
  Stream<double> downloadModel() async* {
    final modelName = DesktopEmbeddingConfig.modelName;

    try {
      debugPrint('[DesktopEmbedding] Starting download of $modelName...');

      // Check if Ollama is running first
      if (!await isOllamaRunning()) {
        throw Exception(
          'Ollama is not running.\n\n'
          'Please install and start Ollama:\n\n'
          'macOS:\n'
          '  brew install ollama\n'
          '  (Ollama starts automatically after install)\n\n'
          'Linux/Windows:\n'
          '  Download from https://ollama.com\n'
          '  Then run: ollama serve',
        );
      }

      yield 0.0; // Starting

      // Use streaming pull to get real progress updates
      final stream = _client.pullModelStream(
        request: PullModelRequest(model: modelName),
      );

      String? lastStatus;
      await for (final response in stream) {
        final total = response.total ?? 0;
        final completed = response.completed ?? 0;
        final status = response.status?.name ?? 'downloading';

        // Log status changes
        if (status != lastStatus) {
          debugPrint('[DesktopEmbedding] Status: $status');
          lastStatus = status;
        }

        // Calculate progress (0.0 to 1.0)
        if (total > 0) {
          final progress = completed / total;
          yield progress.clamp(0.0, 0.99); // Reserve 1.0 for completion
        }
      }

      debugPrint('[DesktopEmbedding] EmbeddingGemma downloaded');
      yield 1.0;
    } catch (e) {
      debugPrint('[DesktopEmbedding] Download failed: $e');
      rethrow;
    }
  }

  /// Embed a single text string
  ///
  /// Returns a 256-dimensional embedding (truncated from 768 via Matryoshka).
  @override
  Future<List<double>> embed(String text) async {
    if (text.trim().isEmpty) {
      throw ArgumentError('Text cannot be empty');
    }

    final modelName = DesktopEmbeddingConfig.modelName;

    try {
      debugPrint(
        '[DesktopEmbedding] Embedding: '
        '${text.substring(0, text.length > 50 ? 50 : text.length)}...',
      );

      final response = await _client.generateEmbedding(
        request: GenerateEmbeddingRequest(
          model: modelName,
          prompt: text,
        ),
      );

      if (response.embedding == null || response.embedding!.isEmpty) {
        throw Exception('Ollama returned empty embedding');
      }

      final fullEmbedding = response.embedding!;

      // Truncate to 256 dimensions (Matryoshka)
      final truncated = EmbeddingDimensionHelper.truncate(
        fullEmbedding,
        DesktopEmbeddingConfig.targetDimensions,
        renormalize: true,
      );

      debugPrint('[DesktopEmbedding] Generated ${truncated.length}d embedding');
      return truncated;
    } catch (e) {
      debugPrint('[DesktopEmbedding] Embedding failed: $e');
      rethrow;
    }
  }

  /// Embed multiple texts
  ///
  /// Processes sequentially since Ollama doesn't support batch embedding.
  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (texts.isEmpty) return [];

    for (int i = 0; i < texts.length; i++) {
      if (texts[i].trim().isEmpty) {
        throw ArgumentError('Text at index $i is empty');
      }
    }

    debugPrint('[DesktopEmbedding] Embedding batch of ${texts.length} texts...');

    try {
      final embeddings = <List<double>>[];
      for (int i = 0; i < texts.length; i++) {
        if (i % 10 == 0 || i == texts.length - 1) {
          debugPrint('[DesktopEmbedding] Progress: ${i + 1}/${texts.length}');
        }
        final embedding = await embed(texts[i]);
        embeddings.add(embedding);
      }

      debugPrint('[DesktopEmbedding] Batch complete');
      return embeddings;
    } catch (e) {
      debugPrint('[DesktopEmbedding] Batch failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    debugPrint('[DesktopEmbedding] Disposing');
    _client.endSession();
  }
}
