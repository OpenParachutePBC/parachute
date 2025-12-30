import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_daily/core/models/embedding_models.dart';
import 'package:parachute_daily/core/services/embedding/embedding_service.dart';
import 'package:parachute_daily/core/services/embedding/embedding_model_manager.dart';
import 'package:parachute_daily/core/services/embedding/mobile_embedding_service.dart';
import 'package:parachute_daily/core/services/embedding/desktop_embedding_service.dart';

/// Provider for mobile embedding service (Android/iOS)
///
/// Uses flutter_gemma_embedder with EmbeddingGemma model.
final mobileEmbeddingServiceProvider = Provider<EmbeddingService>((ref) {
  final service = MobileEmbeddingService();

  ref.onDispose(() async {
    await service.dispose();
  });

  return service;
});

/// Provider for desktop embedding service (macOS/Linux/Windows)
///
/// Uses Ollama with embedding models.
final desktopEmbeddingServiceProvider = Provider<EmbeddingService>((ref) {
  final service = DesktopEmbeddingService();

  ref.onDispose(() async {
    await service.dispose();
  });

  return service;
});

/// Provider for the embedding service
///
/// Automatically selects the appropriate implementation based on platform:
/// - Mobile (Android/iOS): flutter_gemma_embedder
/// - Desktop (macOS/Linux/Windows): Ollama
final embeddingServiceProvider = Provider<EmbeddingService>((ref) {
  if (Platform.isAndroid || Platform.isIOS) {
    return ref.watch(mobileEmbeddingServiceProvider);
  } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    return ref.watch(desktopEmbeddingServiceProvider);
  } else {
    throw UnimplementedError(
      'Embedding service not available on this platform: ${Platform.operatingSystem}',
    );
  }
});

/// Provider for the embedding model manager
///
/// Manages model download lifecycle and status tracking.
final embeddingModelManagerProvider = Provider<EmbeddingModelManager>((ref) {
  final embeddingService = ref.watch(embeddingServiceProvider);
  final manager = EmbeddingModelManager(embeddingService);

  ref.onDispose(() async {
    await manager.dispose();
  });

  return manager;
});

/// Get platform-appropriate model size in MB
int getEmbeddingModelSizeMB() {
  if (Platform.isAndroid || Platform.isIOS) {
    return EmbeddingGemmaModelType.standard.sizeInMB; // 300MB
  } else {
    return DesktopEmbeddingConfig.sizeInMB; // 200MB
  }
}

/// State for embedding model status notifier
class EmbeddingStatusState {
  final EmbeddingModelStatus status;
  final double progress;
  final String? error;
  final bool isReady;
  final bool isDownloading;

  const EmbeddingStatusState({
    this.status = EmbeddingModelStatus.notDownloaded,
    this.progress = 0.0,
    this.error,
    this.isReady = false,
    this.isDownloading = false,
  });

  EmbeddingStatusState copyWith({
    EmbeddingModelStatus? status,
    double? progress,
    String? error,
    bool? isReady,
    bool? isDownloading,
  }) {
    return EmbeddingStatusState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error,
      isReady: isReady ?? this.isReady,
      isDownloading: isDownloading ?? this.isDownloading,
    );
  }
}

/// Notifier that tracks actual embedding model status
class EmbeddingStatusNotifier extends StateNotifier<EmbeddingStatusState> {
  final Ref _ref;

  EmbeddingStatusNotifier(this._ref) : super(const EmbeddingStatusState()) {
    // Check status on creation
    checkStatus();
  }

  /// Check current model status
  Future<void> checkStatus() async {
    try {
      final manager = _ref.read(embeddingModelManagerProvider);
      final isReady = await manager.isReady();

      if (isReady) {
        state = state.copyWith(
          status: EmbeddingModelStatus.ready,
          isReady: true,
          isDownloading: false,
        );
      } else {
        state = state.copyWith(
          status: EmbeddingModelStatus.notDownloaded,
          isReady: false,
          isDownloading: false,
        );
      }
      debugPrint('[EmbeddingStatus] Status check: isReady=$isReady');
    } catch (e) {
      debugPrint('[EmbeddingStatus] Error checking status: $e');
      state = state.copyWith(
        status: EmbeddingModelStatus.error,
        error: e.toString(),
        isReady: false,
        isDownloading: false,
      );
    }
  }

  /// Download the embedding model
  Future<void> download() async {
    if (state.isDownloading) {
      debugPrint('[EmbeddingStatus] Download already in progress');
      return;
    }

    try {
      state = state.copyWith(
        status: EmbeddingModelStatus.downloading,
        isDownloading: true,
        progress: 0.0,
        error: null,
      );

      final manager = _ref.read(embeddingModelManagerProvider);
      await for (final progress in manager.downloadModel()) {
        state = state.copyWith(progress: progress);
        debugPrint('[EmbeddingStatus] Download progress: ${(progress * 100).toStringAsFixed(1)}%');
      }

      state = state.copyWith(
        status: EmbeddingModelStatus.ready,
        isReady: true,
        isDownloading: false,
        progress: 1.0,
      );
      debugPrint('[EmbeddingStatus] Download complete');
    } catch (e) {
      debugPrint('[EmbeddingStatus] Download error: $e');
      state = state.copyWith(
        status: EmbeddingModelStatus.error,
        error: e.toString(),
        isDownloading: false,
      );
    }
  }
}

/// Provider for embedding model status with proper state management
///
/// This properly tracks the actual status of the embedding model,
/// syncing with the underlying service.
final embeddingModelStatusProvider =
    StateNotifierProvider<EmbeddingStatusNotifier, EmbeddingStatusState>((ref) {
  return EmbeddingStatusNotifier(ref);
});

/// State provider for download progress
///
/// Tracks download progress from 0.0 to 1.0.
/// Only meaningful when status is downloading.
final embeddingDownloadProgressProvider = Provider<double>((ref) {
  return ref.watch(embeddingModelStatusProvider).progress;
});

/// State provider for error message
///
/// Contains error message when status is error.
final embeddingErrorProvider = Provider<String?>((ref) {
  return ref.watch(embeddingModelStatusProvider).error;
});

/// Provider for embedding dimensions
///
/// Returns the number of dimensions for embeddings on this platform.
/// All platforms use 256 dimensions for consistency and cross-device sync:
/// - Mobile: 256 (EmbeddingGemma truncated from 768)
/// - Desktop: 256 (Ollama models truncated to match mobile)
final embeddingDimensionsProvider = Provider<int>((ref) {
  final manager = ref.watch(embeddingModelManagerProvider);
  return manager.dimensions;
});
