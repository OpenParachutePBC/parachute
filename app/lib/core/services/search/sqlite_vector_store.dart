import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:app/core/services/search/vector_store.dart';
import 'package:app/core/services/search/models/indexed_chunk.dart';
import 'package:app/core/services/search/models/vector_search_result.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Pure Dart SQLite-based vector store with cosine similarity search
///
/// Performance characteristics:
/// - Storage: ~10MB for 10,000 vectors at 256 dimensions
/// - Search: <100ms for 10,000 vectors (linear scan)
/// - Pre-normalized embeddings for faster cosine similarity
///
/// Future optimization opportunities:
/// - Batch loading for memory efficiency
/// - Approximate nearest neighbor (LSH, IVF)
/// - SIMD-like optimizations using typed_data
class SqliteVectorStore implements VectorStore {
  final String _dbPath;
  Database? _db;
  bool _isInitialized = false;

  SqliteVectorStore(this._dbPath);

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('[VectorStore] Initializing database at: $_dbPath');

      // Ensure directory exists
      final dbFile = File(_dbPath);
      if (!await dbFile.parent.exists()) {
        await dbFile.parent.create(recursive: true);
        debugPrint('[VectorStore] Created database directory');
      }

      // Open database
      _db = sqlite3.open(_dbPath);
      debugPrint('[VectorStore] Database opened');

      // Create schema
      _createSchema();
      debugPrint('[VectorStore] Schema created');

      _isInitialized = true;
      debugPrint('[VectorStore] Initialization complete');
    } catch (e, stackTrace) {
      debugPrint('[VectorStore] Error during initialization: $e');
      debugPrint('[VectorStore] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Create database schema
  void _createSchema() {
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS chunks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recording_id TEXT NOT NULL,
        field TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        chunk_text TEXT NOT NULL,
        embedding BLOB NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(recording_id, field, chunk_index)
      )
    ''');

    _db!.execute('''
      CREATE INDEX IF NOT EXISTS idx_chunks_recording
      ON chunks(recording_id)
    ''');

    _db!.execute('''
      CREATE TABLE IF NOT EXISTS index_manifest (
        recording_id TEXT PRIMARY KEY,
        content_hash TEXT NOT NULL,
        indexed_at TEXT NOT NULL,
        chunk_count INTEGER NOT NULL
      )
    ''');

    debugPrint('[VectorStore] Schema created successfully');
  }

  @override
  Future<void> addChunks(List<IndexedChunk> chunks) async {
    if (!_isInitialized) await initialize();
    if (chunks.isEmpty) return;

    try {
      debugPrint('[VectorStore] Adding ${chunks.length} chunks');

      // Use transaction for atomicity and performance
      _db!.execute('BEGIN TRANSACTION');

      try {
        // Remove existing chunks for these recordings
        final recordingIds = chunks.map((c) => c.recordingId).toSet();
        for (final recordingId in recordingIds) {
          _db!.execute(
            'DELETE FROM chunks WHERE recording_id = ?',
            [recordingId],
          );
        }

        // Insert new chunks
        final stmt = _db!.prepare('''
          INSERT INTO chunks (recording_id, field, chunk_index, chunk_text, embedding, created_at)
          VALUES (?, ?, ?, ?, ?, ?)
        ''');

        for (final chunk in chunks) {
          // Normalize embedding before storing
          final normalizedEmbedding = _normalizeVector(chunk.embedding);
          final embeddingBlob = _floatsToBlob(normalizedEmbedding);

          stmt.execute([
            chunk.recordingId,
            chunk.field,
            chunk.chunkIndex,
            chunk.chunkText,
            embeddingBlob,
            chunk.createdAt.toIso8601String(),
          ]);
        }

        stmt.dispose();

        _db!.execute('COMMIT');
        debugPrint('[VectorStore] Successfully added ${chunks.length} chunks');
      } catch (e) {
        _db!.execute('ROLLBACK');
        rethrow;
      }
    } catch (e, stackTrace) {
      debugPrint('[VectorStore] Error adding chunks: $e');
      debugPrint('[VectorStore] Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<bool> removeChunks(String recordingId) async {
    if (!_isInitialized) await initialize();

    try {
      debugPrint('[VectorStore] Removing chunks for recording: $recordingId');

      // Check if chunks exist
      final result = _db!.select(
        'SELECT COUNT(*) as count FROM chunks WHERE recording_id = ?',
        [recordingId],
      );

      final count = result.first['count'] as int;

      if (count == 0) {
        debugPrint('[VectorStore] No chunks found to remove');
        return false;
      }

      // Delete chunks
      _db!.execute(
        'DELETE FROM chunks WHERE recording_id = ?',
        [recordingId],
      );

      // Delete manifest entry
      _db!.execute(
        'DELETE FROM index_manifest WHERE recording_id = ?',
        [recordingId],
      );

      debugPrint('[VectorStore] Removed $count chunks');
      return true;
    } catch (e, stackTrace) {
      debugPrint('[VectorStore] Error removing chunks: $e');
      debugPrint('[VectorStore] Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<bool> isIndexed(String recordingId) async {
    if (!_isInitialized) await initialize();

    try {
      final result = _db!.select(
        'SELECT COUNT(*) as count FROM chunks WHERE recording_id = ?',
        [recordingId],
      );

      return (result.first['count'] as int) > 0;
    } catch (e) {
      debugPrint('[VectorStore] Error checking if indexed: $e');
      return false;
    }
  }

  @override
  Future<String?> getContentHash(String recordingId) async {
    if (!_isInitialized) await initialize();

    try {
      final result = _db!.select(
        'SELECT content_hash FROM index_manifest WHERE recording_id = ?',
        [recordingId],
      );

      if (result.isEmpty) return null;
      return result.first['content_hash'] as String;
    } catch (e) {
      debugPrint('[VectorStore] Error getting content hash: $e');
      return null;
    }
  }

  @override
  Future<void> updateManifest(
    String recordingId,
    String contentHash,
    int chunkCount,
  ) async {
    if (!_isInitialized) await initialize();

    try {
      debugPrint(
        '[VectorStore] Updating manifest for $recordingId: $chunkCount chunks, hash: $contentHash',
      );

      _db!.execute('''
        INSERT OR REPLACE INTO index_manifest (recording_id, content_hash, indexed_at, chunk_count)
        VALUES (?, ?, ?, ?)
      ''', [
        recordingId,
        contentHash,
        DateTime.now().toIso8601String(),
        chunkCount,
      ]);

      debugPrint('[VectorStore] Manifest updated');
    } catch (e, stackTrace) {
      debugPrint('[VectorStore] Error updating manifest: $e');
      debugPrint('[VectorStore] Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<List<VectorSearchResult>> search(
    List<double> queryEmbedding, {
    int limit = 20,
    double minScore = 0.0,
  }) async {
    if (!_isInitialized) await initialize();

    try {
      debugPrint('[VectorStore] Searching with query embedding (${queryEmbedding.length} dims)');

      // Normalize query embedding for cosine similarity
      final normalizedQuery = _normalizeVector(queryEmbedding);

      // Load all chunks (for small datasets this is fine)
      // Future optimization: batch loading, early termination, approximate NN
      final rows = _db!.select(
        'SELECT id, recording_id, field, chunk_index, chunk_text, embedding FROM chunks',
      );

      debugPrint('[VectorStore] Computing similarity for ${rows.length} chunks');

      final results = <VectorSearchResult>[];

      for (final row in rows) {
        final embedding = _blobToFloats(row['embedding'] as Uint8List);
        final score = _cosineSimilarity(normalizedQuery, embedding);

        if (score >= minScore) {
          results.add(VectorSearchResult(
            chunkId: row['id'] as int,
            recordingId: row['recording_id'] as String,
            field: row['field'] as String,
            chunkIndex: row['chunk_index'] as int,
            chunkText: row['chunk_text'] as String,
            score: score,
          ));
        }
      }

      // Sort by score descending
      results.sort((a, b) => b.score.compareTo(a.score));

      // Return top N
      final topResults = results.take(limit).toList();
      debugPrint('[VectorStore] Returning ${topResults.length} results (max score: ${topResults.isNotEmpty ? topResults.first.score.toStringAsFixed(4) : "N/A"})');

      return topResults;
    } catch (e, stackTrace) {
      debugPrint('[VectorStore] Error during search: $e');
      debugPrint('[VectorStore] Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<List<String>> getIndexedRecordingIds() async {
    if (!_isInitialized) await initialize();

    try {
      final result = _db!.select(
        'SELECT DISTINCT recording_id FROM chunks ORDER BY recording_id',
      );

      return result.map((row) => row['recording_id'] as String).toList();
    } catch (e) {
      debugPrint('[VectorStore] Error getting indexed recording IDs: $e');
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    if (!_isInitialized) await initialize();

    try {
      // Count total chunks
      final chunksResult = _db!.select('SELECT COUNT(*) as count FROM chunks');
      final totalChunks = chunksResult.first['count'] as int;

      // Count unique recordings
      final recordingsResult = _db!.select(
        'SELECT COUNT(DISTINCT recording_id) as count FROM chunks',
      );
      final totalRecordings = recordingsResult.first['count'] as int;

      // Estimate total size (approximate)
      final dbFile = File(_dbPath);
      final totalSize = await dbFile.exists() ? await dbFile.length() : 0;

      return {
        'totalChunks': totalChunks,
        'totalRecordings': totalRecordings,
        'totalSize': totalSize,
      };
    } catch (e) {
      debugPrint('[VectorStore] Error getting stats: $e');
      return {
        'totalChunks': 0,
        'totalRecordings': 0,
        'totalSize': 0,
      };
    }
  }

  @override
  Future<void> clear() async {
    if (!_isInitialized) await initialize();

    try {
      debugPrint('[VectorStore] Clearing all data');

      _db!.execute('DELETE FROM chunks');
      _db!.execute('DELETE FROM index_manifest');

      debugPrint('[VectorStore] All data cleared');
    } catch (e, stackTrace) {
      debugPrint('[VectorStore] Error clearing data: $e');
      debugPrint('[VectorStore] Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_db != null) {
      debugPrint('[VectorStore] Closing database');
      _db!.dispose();
      _db = null;
      _isInitialized = false;
      debugPrint('[VectorStore] Database closed');
    }
  }

  // ========================================================================
  // Vector Operations
  // ========================================================================

  /// Normalize a vector to unit length (L2 normalization)
  ///
  /// For pre-normalized vectors, cosine similarity becomes dot product,
  /// which is faster to compute.
  List<double> _normalizeVector(List<double> vector) {
    double norm = 0.0;
    for (final val in vector) {
      norm += val * val;
    }
    norm = math.sqrt(norm);

    if (norm == 0.0) {
      // Zero vector - return as-is
      return List<double>.from(vector);
    }

    return vector.map((val) => val / norm).toList();
  }

  /// Compute cosine similarity between two vectors
  ///
  /// Assumes both vectors are already normalized.
  /// Returns value in range [0.0, 1.0] where:
  /// - 1.0 = identical vectors
  /// - 0.0 = orthogonal (no similarity)
  ///
  /// For normalized vectors: cosine_similarity = dot_product
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Vectors must have same length');
    }

    double dotProduct = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
    }

    // Clamp to [0, 1] to handle floating point errors
    // (normalized vectors should always give result in [-1, 1])
    return dotProduct.clamp(0.0, 1.0);
  }

  // ========================================================================
  // BLOB Conversion
  // ========================================================================

  /// Convert a list of doubles to a BLOB (byte array)
  ///
  /// Uses Float32 (4 bytes per value) for storage efficiency.
  /// Little-endian byte order for cross-platform consistency.
  Uint8List _floatsToBlob(List<double> floats) {
    final byteData = ByteData(floats.length * 4);
    for (int i = 0; i < floats.length; i++) {
      byteData.setFloat32(i * 4, floats[i], Endian.little);
    }
    return byteData.buffer.asUint8List();
  }

  /// Convert a BLOB (byte array) back to a list of doubles
  List<double> _blobToFloats(Uint8List blob) {
    final byteData = ByteData.sublistView(blob);
    final floats = <double>[];
    for (int i = 0; i < blob.length; i += 4) {
      floats.add(byteData.getFloat32(i, Endian.little));
    }
    return floats;
  }

  // ========================================================================
  // Utility Methods
  // ========================================================================

  /// Compute SHA-256 hash of content for change detection
  static String computeContentHash(String content) {
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
