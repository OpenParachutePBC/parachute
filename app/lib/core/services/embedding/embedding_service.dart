import 'dart:math' as math;

/// Abstract interface for text embedding services
///
/// Provides a common interface for platform-specific embedding implementations:
/// - Mobile (Android/iOS): flutter_gemma with EmbeddingGemma
/// - Desktop (macOS/Linux/Windows): Ollama with embedding models
///
/// This allows the rest of the system to work with embeddings without
/// caring about which backend is being used.
abstract class EmbeddingService {
  /// Check if the embedding model is ready to use
  ///
  /// Returns true if the model is downloaded and loaded.
  Future<bool> isReady();

  /// Check if the model needs to be downloaded
  ///
  /// Returns true if the model has not been downloaded yet.
  Future<bool> needsDownload();

  /// Download the model
  ///
  /// Streams download progress from 0.0 to 1.0.
  /// The stream completes when the download finishes.
  ///
  /// Throws an exception if the download fails.
  Stream<double> downloadModel();

  /// Get embedding dimensions
  ///
  /// Returns the number of dimensions in the embedding vectors
  /// (e.g., 256, 512, 768, 1024).
  ///
  /// This is needed for:
  /// - Allocating vector storage
  /// - Configuring vector search indices
  /// - Truncating higher-dimensional embeddings (Matryoshka)
  int get dimensions;

  /// Embed a single text string
  ///
  /// Returns a normalized embedding vector of length [dimensions].
  ///
  /// Throws an exception if:
  /// - The model is not ready (call [isReady] first)
  /// - Text is empty
  /// - Embedding generation fails
  Future<List<double>> embed(String text);

  /// Embed multiple texts in a batch
  ///
  /// More efficient than calling [embed] multiple times.
  /// Returns a list of normalized embedding vectors.
  ///
  /// Throws an exception if:
  /// - The model is not ready (call [isReady] first)
  /// - Any text is empty
  /// - Embedding generation fails
  Future<List<List<double>>> embedBatch(List<String> texts);

  /// Release resources held by the service
  ///
  /// Call this when the service is no longer needed.
  /// After disposal, the service cannot be used again.
  Future<void> dispose();
}

/// Helper functions for dimension truncation (Matryoshka embeddings)
///
/// EmbeddingGemma supports truncating from 768 to smaller sizes:
/// - 768: Best quality, slowest search, largest storage
/// - 512: Good quality, moderate search, moderate storage
/// - 256: ~97% quality, 3x faster search, 1/3 storage
///
/// See: https://arxiv.org/abs/2205.13147
class EmbeddingDimensionHelper {
  /// Truncate an embedding vector to the specified number of dimensions
  ///
  /// Uses the first N dimensions (Matryoshka property).
  ///
  /// [embedding] must have at least [targetDimensions] elements.
  /// [renormalize] controls whether to normalize after truncation (recommended: true)
  static List<double> truncate(
    List<double> embedding,
    int targetDimensions, {
    bool renormalize = true,
  }) {
    if (embedding.length < targetDimensions) {
      throw ArgumentError(
        'Cannot truncate embedding of length ${embedding.length} to $targetDimensions',
      );
    }

    // Take first N dimensions
    final truncated = embedding.sublist(0, targetDimensions);

    // Renormalize to unit length
    if (renormalize) {
      return _normalize(truncated);
    }

    return truncated;
  }

  /// Normalize a vector to unit length (L2 norm = 1)
  ///
  /// This is important for cosine similarity to work correctly.
  static List<double> _normalize(List<double> vector) {
    // Calculate L2 norm (magnitude)
    double sumSquares = 0.0;
    for (final value in vector) {
      sumSquares += value * value;
    }
    final magnitude = math.sqrt(sumSquares);

    // Avoid division by zero
    if (magnitude == 0.0) {
      return vector;
    }

    // Divide each component by magnitude
    return vector.map((v) => v / magnitude).toList();
  }

  /// Check if a vector is normalized (for testing)
  static bool isNormalized(List<double> vector, {double tolerance = 1e-6}) {
    double sumSquares = 0.0;
    for (final value in vector) {
      sumSquares += value * value;
    }
    final magnitude = math.sqrt(sumSquares);
    return (magnitude - 1.0).abs() < tolerance;
  }
}
