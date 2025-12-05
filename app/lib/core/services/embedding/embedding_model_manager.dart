import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:app/core/models/embedding_models.dart';
import 'package:app/core/services/embedding/embedding_service.dart';

/// Manages embedding model lifecycle across platforms
///
/// Handles:
/// - Platform detection (mobile vs desktop)
/// - Model download management
/// - Status tracking for UI feedback
/// - Automatic model loading on app startup
///
/// Usage:
/// ```dart
/// final manager = EmbeddingModelManager(embeddingService);
/// await manager.ensureModelReady(); // Triggers download if needed
/// final status = manager.status;    // Check current status
/// ```
class EmbeddingModelManager {
  final EmbeddingService _embeddingService;

  EmbeddingModelStatus _status = EmbeddingModelStatus.notDownloaded;
  double _downloadProgress = 0.0;
  String? _error;

  EmbeddingModelManager(this._embeddingService);

  /// Current model status
  EmbeddingModelStatus get status => _status;

  /// Current download progress (0.0 to 1.0)
  double get downloadProgress => _downloadProgress;

  /// Error message if status is error
  String? get error => _error;

  /// Get the embedding service instance
  EmbeddingService get service => _embeddingService;

  /// Ensure the model is ready for use
  ///
  /// This should be called on app startup (non-blocking).
  /// It will:
  /// 1. Check if model needs download
  /// 2. Download if needed (streaming progress)
  /// 3. Update status accordingly
  ///
  /// Safe to call multiple times - will skip if already ready.
  Future<void> ensureModelReady() async {
    try {
      debugPrint('[EmbeddingModelManager] Checking model status...');

      // Check if already ready
      final isReady = await _embeddingService.isReady();
      if (isReady) {
        debugPrint('[EmbeddingModelManager] ✅ Model already ready');
        _status = EmbeddingModelStatus.ready;
        return;
      }

      // Check if needs download
      final needsDownload = await _embeddingService.needsDownload();
      if (!needsDownload) {
        debugPrint('[EmbeddingModelManager] ✅ Model downloaded but not loaded');
        _status = EmbeddingModelStatus.ready;
        return;
      }

      // Download the model
      debugPrint('[EmbeddingModelManager] Model needs download, starting...');
      _status = EmbeddingModelStatus.downloading;
      _downloadProgress = 0.0;

      await for (final progress in _embeddingService.downloadModel()) {
        _downloadProgress = progress;
        debugPrint(
          '[EmbeddingModelManager] Download progress: ${(progress * 100).toStringAsFixed(1)}%',
        );
      }

      // Download complete
      debugPrint('[EmbeddingModelManager] ✅ Download complete');
      _status = EmbeddingModelStatus.ready;
      _downloadProgress = 1.0;
    } catch (e, stackTrace) {
      debugPrint('[EmbeddingModelManager] ❌ Error ensuring model ready: $e');
      debugPrint('[EmbeddingModelManager] Stack trace: $stackTrace');
      _status = EmbeddingModelStatus.error;
      _error = e.toString();
    }
  }

  /// Get platform-appropriate embedding dimensions
  ///
  /// Returns the number of dimensions for the current platform:
  /// - Mobile: 256 (truncated from 768 for speed)
  /// - Desktop: Depends on Ollama model (768 or 1024)
  int get dimensions => _embeddingService.dimensions;

  /// Check if the model is ready to use
  Future<bool> isReady() => _embeddingService.isReady();

  /// Manually trigger a download (for UI buttons)
  ///
  /// Returns a stream of progress updates (0.0 to 1.0).
  Stream<double> downloadModel() async* {
    try {
      _status = EmbeddingModelStatus.downloading;
      _downloadProgress = 0.0;
      _error = null;

      await for (final progress in _embeddingService.downloadModel()) {
        _downloadProgress = progress;
        yield progress;
      }

      _status = EmbeddingModelStatus.ready;
      _downloadProgress = 1.0;
    } catch (e) {
      _status = EmbeddingModelStatus.error;
      _error = e.toString();
      rethrow;
    }
  }

  /// Check if running on mobile platform
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// Check if running on desktop platform
  static bool get isDesktop =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  /// Dispose of resources
  Future<void> dispose() async {
    await _embeddingService.dispose();
  }
}
