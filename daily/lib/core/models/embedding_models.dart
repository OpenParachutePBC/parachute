/// Embedding model definitions for RAG search
library;

/// Embedding model status
enum EmbeddingModelStatus {
  notDownloaded('Not Downloaded', 'Model needs to be downloaded'),
  downloading('Downloading', 'Model is being downloaded'),
  ready('Ready', 'Model is ready to use'),
  error('Error', 'Model download or initialization failed');

  const EmbeddingModelStatus(this.displayName, this.description);

  final String displayName;
  final String description;

  bool get isReady => this == EmbeddingModelStatus.ready;
  bool get isDownloading => this == EmbeddingModelStatus.downloading;
  bool get needsDownload => this == EmbeddingModelStatus.notDownloaded;
  bool get hasError => this == EmbeddingModelStatus.error;
}

/// Embedding model types for mobile platforms (Android/iOS)
///
/// Uses EmbeddingGemma via flutter_gemma for on-device embedding generation.
/// Supports Matryoshka embeddings - can truncate from 768 to smaller sizes.
///
/// Models are hosted on Parachute CDN for easy download (no HuggingFace token required).
enum EmbeddingGemmaModelType {
  /// Default embedding model (256 dimensions, truncated from 768)
  /// Recommended for most users - 3x faster search, ~97% quality vs 768
  standard(
    'embedding-gemma-256',
    300,
    'Standard embedding model - 256 dimensions',
    'https://pub-83d77b23427846aa85d32982f50d7f18.r2.dev/embedding-gemma.task',
    'https://huggingface.co/google/embedding-gemma',
    256,
  );

  const EmbeddingGemmaModelType(
    this.modelName,
    this.sizeInMB,
    this.description,
    this.downloadUrl,
    this.huggingFaceUrl,
    this.dimensions,
  );

  final String modelName;
  final int sizeInMB;
  final String description;
  final String downloadUrl;
  final String huggingFaceUrl;
  final int dimensions;

  /// Get formatted size string (e.g., "300 MB", "1.2 GB")
  String get formattedSize {
    if (sizeInMB < 1000) {
      return '$sizeInMB MB';
    } else {
      final sizeInGB = sizeInMB / 1000;
      return '${sizeInGB.toStringAsFixed(1)} GB';
    }
  }

  /// Get display name for UI
  String get displayName {
    return modelName.toUpperCase();
  }

  /// Get full display text with size
  String get fullDisplayName {
    return '$displayName ($formattedSize)';
  }

  /// Convert string to enum (case-insensitive)
  static EmbeddingGemmaModelType? fromString(String value) {
    final normalized = value.toLowerCase();
    for (final model in EmbeddingGemmaModelType.values) {
      if (model.modelName == normalized ||
          model.name.toLowerCase() == normalized) {
        return model;
      }
    }
    return null;
  }
}

/// Desktop embedding configuration (macOS/Linux/Windows)
///
/// Uses Ollama with EmbeddingGemma for compatibility with mobile.
/// This is a singleton configuration, not a choice - we use the same
/// model everywhere for cross-device compatibility.
class DesktopEmbeddingConfig {
  /// Model name in Ollama
  static const String modelName = 'embeddinggemma';

  /// Approximate download size in MB
  static const int sizeInMB = 200;

  /// Native dimensions before truncation
  static const int nativeDimensions = 768;

  /// Target dimensions after Matryoshka truncation
  static const int targetDimensions = 256;

  /// Human-readable description
  static const String description = 'EmbeddingGemma - same model as mobile';

  /// Get formatted size string
  static String get formattedSize => '$sizeInMB MB';

  /// Get display name for UI
  static String get displayName => 'EmbeddingGemma';

  /// Get full display text with size
  static String get fullDisplayName => '$displayName ($formattedSize)';
}

/// Model download progress data
class EmbeddingModelDownloadProgress {
  final String modelName;
  final EmbeddingModelStatus status;
  final double progress; // 0.0 to 1.0
  final String? error;

  const EmbeddingModelDownloadProgress({
    required this.modelName,
    required this.status,
    this.progress = 0.0,
    this.error,
  });

  EmbeddingModelDownloadProgress copyWith({
    String? modelName,
    EmbeddingModelStatus? status,
    double? progress,
    String? error,
  }) {
    return EmbeddingModelDownloadProgress(
      modelName: modelName ?? this.modelName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
    );
  }

  /// Get formatted progress percentage
  String get progressPercentage {
    return '${(progress * 100).toStringAsFixed(0)}%';
  }

  bool get isReady => status.isReady;
  bool get isDownloading => status.isDownloading;
  bool get needsDownload => status.needsDownload;
  bool get hasError => status.hasError;
}
