import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/services/search/search_index_service.dart';
import 'package:app/core/services/search/content_hasher.dart';
import 'package:app/core/services/search/chunking/recording_chunker.dart';
import 'package:app/core/services/search/hybrid_search_service.dart';
import 'package:app/core/services/search/models/search_result.dart';
import 'package:app/core/providers/vector_store_provider.dart';
import 'package:app/core/providers/bm25_provider.dart';
import 'package:app/core/providers/embedding_provider.dart';
import 'package:app/features/recorder/providers/service_providers.dart';

// Export for convenience
export 'package:app/core/services/search/search_index_service.dart' show IndexingStatus;
export 'package:app/core/services/search/models/search_result.dart';

/// Provider for ContentHasher
///
/// Stateless utility for computing content hashes.
final contentHasherProvider = Provider<ContentHasher>((ref) {
  return ContentHasher();
});

/// Provider for RecordingChunker
///
/// Chunks recordings into IndexedChunk objects with embeddings.
/// Uses the embedding service to generate embeddings for each chunk.
final recordingChunkerProvider = Provider<RecordingChunker>((ref) {
  final embeddingService = ref.watch(embeddingServiceProvider);
  return RecordingChunker(embeddingService);
});

/// Provider for SearchIndexService
///
/// The main orchestrator for search indexing. Coordinates:
/// - Change detection via content hashing
/// - Chunking recordings
/// - Storing embeddings in vector store
/// - Rebuilding BM25 index
///
/// **Usage:**
/// ```dart
/// final searchIndex = ref.read(searchIndexServiceProvider);
///
/// // Background sync on app start
/// searchIndex.syncIndexes();
///
/// // Immediate indexing on save
/// await searchIndex.indexRecording(recording);
///
/// // Remove on delete
/// await searchIndex.removeRecording(recordingId);
///
/// // Monitor progress
/// searchIndex.addListener(() {
///   print('Status: ${searchIndex.status}');
///   print('Progress: ${searchIndex.progress}');
/// });
/// ```
final searchIndexServiceProvider = Provider<SearchIndexService>((ref) {
  final vectorStore = ref.watch(vectorStoreProvider);
  final bm25Manager = ref.watch(bm25IndexManagerProvider);
  final chunker = ref.watch(recordingChunkerProvider);
  final storageService = ref.watch(storageServiceProvider);
  final hasher = ref.watch(contentHasherProvider);

  final service = SearchIndexService(
    vectorStore,
    bm25Manager,
    chunker,
    storageService,
    hasher,
  );

  // Auto-dispose: clean up resources
  ref.onDispose(() async {
    await service.dispose();
  });

  return service;
});

/// State provider for indexing status
///
/// Tracks the current state of the indexing process for UI updates.
/// Use this to show loading indicators or progress bars.
///
/// **Example:**
/// ```dart
/// final status = ref.watch(indexingStatusProvider);
/// if (status == IndexingStatus.indexing) {
///   final progress = ref.watch(indexingProgressProvider);
///   return CircularProgressIndicator(value: progress);
/// }
/// ```
final indexingStatusProvider = StateProvider<IndexingStatus>((ref) {
  return IndexingStatus.idle;
});

/// State provider for indexing progress
///
/// Value from 0.0 to 1.0 representing progress through current indexing operation.
final indexingProgressProvider = StateProvider<double>((ref) {
  return 0.0;
});

/// State provider for indexing error message
///
/// Contains error message when status is IndexingStatus.error.
final indexingErrorProvider = StateProvider<String?>((ref) {
  return null;
});

/// State provider for total items to index
///
/// Number of recordings being processed in current operation.
final indexingTotalProvider = StateProvider<int>((ref) {
  return 0;
});

/// State provider for indexed items count
///
/// Number of recordings processed so far in current operation.
final indexingCountProvider = StateProvider<int>((ref) {
  return 0;
});

// ========================================================================
// Hybrid Search Providers
// ========================================================================

/// Provider for HybridSearchService
///
/// The main search API combining vector (semantic) and BM25 (keyword) search
/// using Reciprocal Rank Fusion (RRF) to merge results.
///
/// **Usage:**
/// ```dart
/// final searchService = ref.read(hybridSearchServiceProvider);
/// final results = await searchService.search('project alpha', limit: 20);
/// ```
final hybridSearchServiceProvider = Provider<HybridSearchService>((ref) {
  final vectorStore = ref.watch(vectorStoreProvider);
  final bm25Service = ref.watch(bm25SearchServiceProvider);
  final embeddingService = ref.watch(embeddingServiceProvider);
  final storageService = ref.watch(storageServiceProvider);

  return HybridSearchService(
    vectorStore,
    bm25Service,
    embeddingService,
    storageService,
  );
});

/// State provider for search query
///
/// Holds the current search query string. Update this to trigger a search.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Future provider for search results
///
/// Automatically runs hybrid search when [searchQueryProvider] changes.
/// Returns empty list for empty queries.
///
/// **Example:**
/// ```dart
/// // In your widget
/// final results = ref.watch(searchResultsProvider);
///
/// return results.when(
///   data: (results) => ListView.builder(
///     itemCount: results.length,
///     itemBuilder: (context, index) {
///       final result = results[index];
///       return SearchResultCard(result: result);
///     },
///   ),
///   loading: () => CircularProgressIndicator(),
///   error: (err, stack) => Text('Search failed: $err'),
/// );
/// ```
final searchResultsProvider = FutureProvider<List<SearchResult>>((ref) async {
  final query = ref.watch(searchQueryProvider);

  if (query.trim().isEmpty) {
    return [];
  }

  final searchService = ref.watch(hybridSearchServiceProvider);
  return await searchService.search(query);
});
