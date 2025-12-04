import 'package:app/core/services/search/models/indexed_chunk.dart';
import 'package:app/core/services/search/models/vector_search_result.dart';

/// Abstract interface for vector storage and similarity search
///
/// Implementations should:
/// - Store embeddings as normalized vectors for efficient cosine similarity
/// - Support CRUD operations on chunks
/// - Track what's been indexed to enable incremental updates
/// - Perform K-nearest-neighbor search using cosine similarity
abstract class VectorStore {
  /// Initialize the store (create tables, open connections, etc.)
  Future<void> initialize();

  /// Add chunks for a recording
  ///
  /// If chunks for this recording already exist, they should be replaced.
  /// This enables re-indexing when content changes.
  Future<void> addChunks(List<IndexedChunk> chunks);

  /// Remove all chunks for a recording
  ///
  /// Returns true if chunks were deleted, false if none existed.
  Future<bool> removeChunks(String recordingId);

  /// Check if recording is indexed
  ///
  /// Returns true if there are any chunks for this recording.
  Future<bool> isIndexed(String recordingId);

  /// Get content hash for a recording (for change detection)
  ///
  /// Returns null if the recording is not indexed.
  Future<String?> getContentHash(String recordingId);

  /// Update manifest after indexing
  ///
  /// Stores metadata about what was indexed and when.
  /// The content hash is used to detect if re-indexing is needed.
  Future<void> updateManifest(
    String recordingId,
    String contentHash,
    int chunkCount,
  );

  /// Search for similar chunks using cosine similarity
  ///
  /// [queryEmbedding] should be normalized for best results.
  /// [limit] controls how many results to return (default: 20).
  /// [minScore] filters out results below this similarity threshold (default: 0.0).
  ///
  /// Returns results sorted by similarity score (highest first).
  Future<List<VectorSearchResult>> search(
    List<double> queryEmbedding, {
    int limit = 20,
    double minScore = 0.0,
  });

  /// Get all indexed recording IDs
  ///
  /// Useful for determining what needs to be indexed.
  Future<List<String>> getIndexedRecordingIds();

  /// Get statistics about the vector store
  ///
  /// Returns a map with keys:
  /// - 'totalChunks': Total number of indexed chunks
  /// - 'totalRecordings': Number of unique recordings indexed
  /// - 'totalSize': Approximate size in bytes
  Future<Map<String, dynamic>> getStats();

  /// Clear all data (for testing/reset)
  ///
  /// Removes all chunks and manifest entries.
  Future<void> clear();

  /// Close the store and release resources
  Future<void> close();
}
