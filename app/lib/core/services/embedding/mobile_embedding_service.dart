import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:app/core/services/embedding/embedding_service.dart';

/// Mobile embedding service using flutter_gemma
///
/// Generates text embeddings on-device using Google's EmbeddingGemma model.
/// Supports Android and iOS with GPU acceleration where available.
///
/// Key features:
/// - 768-dimensional embeddings (truncated to 256 for speed)
/// - Matryoshka embeddings - can truncate without quality loss
/// - <200MB RAM usage with quantization
/// - No network required after model download
class MobileEmbeddingService implements EmbeddingService {
  EmbeddingModel? _model;
  bool _isDisposed = false;

  /// Target dimensions (using Matryoshka truncation from 768)
  static const int _targetDimensions = 256;

  /// Model URLs from HuggingFace
  static const String _modelUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq1024_mixed-precision.tflite';
  static const String _tokenizerUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model';

  @override
  int get dimensions => _targetDimensions;

  @override
  Future<bool> isReady() async {
    if (_isDisposed) {
      debugPrint('[MobileEmbedding] Service is disposed');
      return false;
    }

    // Check if model is loaded in memory
    if (_model != null) {
      debugPrint('[MobileEmbedding] Model already loaded in memory');
      return true;
    }

    // Try to get active embedder if already installed
    try {
      _model = await FlutterGemma.getActiveEmbedder(
        preferredBackend: PreferredBackend.gpu,
      );
      if (_model != null) {
        debugPrint('[MobileEmbedding] Model loaded from existing installation');
        return true;
      }
    } catch (e) {
      debugPrint('[MobileEmbedding] No active embedder available: $e');
    }

    return false;
  }

  @override
  Future<bool> needsDownload() async {
    if (_isDisposed) {
      debugPrint('[MobileEmbedding] Service is disposed');
      return false;
    }

    // Try to check if model is already installed
    try {
      final embedder = await FlutterGemma.getActiveEmbedder(
        preferredBackend: PreferredBackend.gpu,
      );
      await embedder.close();
      debugPrint('[MobileEmbedding] Model already installed');
      return false;
    } catch (e) {
      debugPrint('[MobileEmbedding] Model needs download: $e');
    }

    return true;
  }

  @override
  Stream<double> downloadModel() async* {
    if (_isDisposed) {
      throw Exception('Service is disposed');
    }

    debugPrint('[MobileEmbedding] Starting model download...');

    try {
      // Check if already downloaded
      if (!await needsDownload()) {
        debugPrint('[MobileEmbedding] ✅ Model already downloaded');
        yield 1.0;
        return;
      }

      double modelProgress = 0.0;
      double tokenizerProgress = 0.0;

      // Install model and tokenizer
      await FlutterGemma.installEmbedder()
          .modelFromNetwork(_modelUrl)
          .tokenizerFromNetwork(_tokenizerUrl)
          .withModelProgress((progress) {
            modelProgress = progress / 100.0;
            debugPrint('[MobileEmbedding] Model download: ${progress.toStringAsFixed(1)}%');
          })
          .withTokenizerProgress((progress) {
            tokenizerProgress = progress / 100.0;
            debugPrint('[MobileEmbedding] Tokenizer download: ${progress.toStringAsFixed(1)}%');
          })
          .install();

      // Report combined progress (model is ~95% of download, tokenizer ~5%)
      yield (modelProgress * 0.95) + (tokenizerProgress * 0.05);

      debugPrint('[MobileEmbedding] ✅ Model installed successfully');
      yield 1.0;
    } catch (e, stackTrace) {
      debugPrint('[MobileEmbedding] ❌ Download failed: $e');
      debugPrint('[MobileEmbedding] Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<List<double>> embed(String text) async {
    if (_isDisposed) {
      throw Exception('Service is disposed');
    }

    if (text.trim().isEmpty) {
      throw ArgumentError('Text cannot be empty');
    }

    // Ensure model is loaded
    await _ensureModelLoaded();

    try {
      debugPrint('[MobileEmbedding] Embedding text (${text.length} chars)');

      // Generate 768-dimensional embedding
      final fullEmbedding = await _model!.generateEmbedding(text);

      // Truncate to 256 dimensions (Matryoshka)
      final truncated = EmbeddingDimensionHelper.truncate(
        fullEmbedding,
        _targetDimensions,
        renormalize: true,
      );

      debugPrint('[MobileEmbedding] ✅ Generated embedding (${truncated.length}d)');
      return truncated;
    } catch (e, stackTrace) {
      debugPrint('[MobileEmbedding] ❌ Embedding failed: $e');
      debugPrint('[MobileEmbedding] Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (_isDisposed) {
      throw Exception('Service is disposed');
    }

    if (texts.isEmpty) {
      return [];
    }

    for (final text in texts) {
      if (text.trim().isEmpty) {
        throw ArgumentError('All texts must be non-empty');
      }
    }

    // Ensure model is loaded
    await _ensureModelLoaded();

    try {
      debugPrint('[MobileEmbedding] Embedding batch of ${texts.length} texts');

      // Generate 768-dimensional embeddings
      final fullEmbeddings = await _model!.generateEmbeddings(texts);

      // Truncate each to 256 dimensions (Matryoshka)
      final truncatedEmbeddings = fullEmbeddings.map((embedding) {
        return EmbeddingDimensionHelper.truncate(
          embedding,
          _targetDimensions,
          renormalize: true,
        );
      }).toList();

      debugPrint(
        '[MobileEmbedding] ✅ Generated ${truncatedEmbeddings.length} embeddings (${_targetDimensions}d each)',
      );
      return truncatedEmbeddings;
    } catch (e, stackTrace) {
      debugPrint('[MobileEmbedding] ❌ Batch embedding failed: $e');
      debugPrint('[MobileEmbedding] Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    debugPrint('[MobileEmbedding] Disposing service...');

    try {
      if (_model != null) {
        await _model!.close();
        _model = null;
        debugPrint('[MobileEmbedding] ✅ Model closed');
      }
    } catch (e) {
      debugPrint('[MobileEmbedding] Error disposing model: $e');
    }

    _isDisposed = true;
    debugPrint('[MobileEmbedding] Service disposed');
  }

  /// Ensure the model is loaded and ready to use
  Future<void> _ensureModelLoaded() async {
    if (_model != null) {
      return;
    }

    debugPrint('[MobileEmbedding] Loading model...');

    try {
      _model = await FlutterGemma.getActiveEmbedder(
        preferredBackend: PreferredBackend.gpu,
      );

      if (_model == null) {
        throw Exception(
          'Model is not ready. Please download the model first.',
        );
      }

      debugPrint('[MobileEmbedding] ✅ Model loaded successfully');
      debugPrint('[MobileEmbedding] Using GPU backend if available');
    } catch (e, stackTrace) {
      debugPrint('[MobileEmbedding] ❌ Failed to load model: $e');
      debugPrint('[MobileEmbedding] Stack trace: $stackTrace');
      rethrow;
    }
  }
}
