import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/models/embedding_models.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/embedding/embedding_model_manager.dart';
import 'package:app/core/services/embedding/mobile_embedding_service.dart';
import 'package:app/core/services/embedding/desktop_embedding_service.dart';

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

/// State provider for embedding model status
///
/// Tracks the current status of the embedding model:
/// - notDownloaded: Model needs to be downloaded
/// - downloading: Download in progress
/// - ready: Model is ready to use
/// - error: Download or initialization failed
final embeddingModelStatusProvider =
    StateProvider<EmbeddingModelStatus>((ref) {
  return EmbeddingModelStatus.notDownloaded;
});

/// State provider for download progress
///
/// Tracks download progress from 0.0 to 1.0.
/// Only meaningful when status is downloading.
final embeddingDownloadProgressProvider = StateProvider<double>((ref) {
  return 0.0;
});

/// State provider for error message
///
/// Contains error message when status is error.
final embeddingErrorProvider = StateProvider<String?>((ref) {
  return null;
});

/// Provider for embedding dimensions
///
/// Returns the number of dimensions for embeddings on this platform:
/// - Mobile: 256 (truncated from 768)
/// - Desktop: 768 or 1024 (depends on Ollama model)
final embeddingDimensionsProvider = Provider<int>((ref) {
  final manager = ref.watch(embeddingModelManagerProvider);
  return manager.dimensions;
});
