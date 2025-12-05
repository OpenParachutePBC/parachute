import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app/core/services/search/vector_store.dart';
import 'package:app/core/services/search/sqlite_vector_store.dart';

/// Provider for the vector store database path
///
/// Stores the database in the app's support directory (not synced).
/// Path: {supportDir}/search/vector_store.db
///
/// The database is device-specific and rebuilt per device.
/// This is intentional - embedding models may differ per platform.
final vectorStorePathProvider = FutureProvider<String>((ref) async {
  final supportDir = await getApplicationSupportDirectory();
  final searchDir = Directory('${supportDir.path}/search');

  // Ensure directory exists
  if (!await searchDir.exists()) {
    await searchDir.create(recursive: true);
  }

  return '${searchDir.path}/vector_store.db';
});

/// Provider for the VectorStore implementation
///
/// Uses SQLite-based vector store with cosine similarity search.
/// The store is initialized lazily on first use.
///
/// **Disposal:** The store is automatically closed when the provider
/// is disposed (e.g., app shutdown).
///
/// **Usage:**
/// ```dart
/// final vectorStore = ref.read(vectorStoreProvider);
/// await vectorStore.addChunks(chunks);
/// ```
final vectorStoreProvider = Provider<VectorStore>((ref) {
  // Get the database path synchronously (will throw if not ready)
  final dbPathAsync = ref.watch(vectorStorePathProvider);

  return dbPathAsync.when(
    data: (dbPath) {
      final store = SqliteVectorStore(dbPath);

      // Auto-dispose: close database when provider is disposed
      ref.onDispose(() async {
        await store.close();
      });

      return store;
    },
    loading: () {
      // During initialization, return a placeholder that will throw
      // This shouldn't happen in practice since we await initialization
      throw StateError(
        'VectorStore not ready - database path is still loading',
      );
    },
    error: (error, stackTrace) {
      throw Exception('Failed to initialize VectorStore: $error');
    },
  );
});
