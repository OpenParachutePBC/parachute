import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/services/search/vector_store.dart';
import 'package:app/core/services/search/sqlite_vector_store.dart';
import 'package:app/core/services/file_system_service.dart';

/// Provider for the vector store database path
///
/// Stores the database in the vault's .parachute directory (synced).
/// Path: {vault}/.parachute/search.db
///
/// This allows the search index to be:
/// 1. Synced across devices via Syncthing
/// 2. Accessible by the agent for MCP search tools
///
/// **Note on embeddings:** Different devices may use different embedding
/// models (Gemma on mobile, Ollama on desktop). For best results, use
/// one device as the "indexing source" and others for querying only.
final vectorStorePathProvider = FutureProvider<String>((ref) async {
  final fileSystem = FileSystemService();
  await fileSystem.initialize();

  final vaultPath = await fileSystem.getRootPath();
  final parachuteDir = Directory('$vaultPath/.parachute');

  // Ensure directory exists
  if (!await parachuteDir.exists()) {
    await parachuteDir.create(recursive: true);
  }

  return '${parachuteDir.path}/search.db';
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
