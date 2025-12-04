import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/services/search/sqlite_vector_store.dart';
import 'package:app/core/services/search/models/indexed_chunk.dart';
import 'package:path/path.dart' as p;

void main() {
  group('SqliteVectorStore', () {
    late String testDbPath;
    late SqliteVectorStore store;

    setUp(() async {
      // Create a temporary database file
      final tempDir = Directory.systemTemp.createTempSync('vector_store_test_');
      testDbPath = p.join(tempDir.path, 'test_vector_store.db');
      store = SqliteVectorStore(testDbPath);
      await store.initialize();
    });

    tearDown(() async {
      await store.close();
      // Clean up test database
      final dbFile = File(testDbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      final dbDir = dbFile.parent;
      if (await dbDir.exists()) {
        await dbDir.delete(recursive: true);
      }
    });

    group('Initialization', () {
      test('initializes successfully', () async {
        expect(store, isNotNull);
      });

      test('creates database file', () async {
        expect(await File(testDbPath).exists(), isTrue);
      });

      test('can be initialized multiple times safely', () async {
        await store.initialize();
        await store.initialize();
        expect(await File(testDbPath).exists(), isTrue);
      });
    });

    group('Adding Chunks', () {
      test('adds single chunk successfully', () async {
        final chunk = IndexedChunk(
          recordingId: 'rec1',
          field: 'transcript',
          chunkIndex: 0,
          chunkText: 'This is a test chunk',
          embedding: _generateRandomEmbedding(256),
        );

        await store.addChunks([chunk]);

        final isIndexed = await store.isIndexed('rec1');
        expect(isIndexed, isTrue);
      });

      test('adds multiple chunks for same recording', () async {
        final chunks = [
          IndexedChunk(
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'First chunk',
            embedding: _generateRandomEmbedding(256),
          ),
          IndexedChunk(
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 1,
            chunkText: 'Second chunk',
            embedding: _generateRandomEmbedding(256),
          ),
        ];

        await store.addChunks(chunks);

        final isIndexed = await store.isIndexed('rec1');
        expect(isIndexed, isTrue);
      });

      test('replaces existing chunks when re-adding', () async {
        final chunk1 = IndexedChunk(
          recordingId: 'rec1',
          field: 'transcript',
          chunkIndex: 0,
          chunkText: 'Original text',
          embedding: _generateRandomEmbedding(256),
        );

        await store.addChunks([chunk1]);

        final chunk2 = IndexedChunk(
          recordingId: 'rec1',
          field: 'transcript',
          chunkIndex: 0,
          chunkText: 'Updated text',
          embedding: _generateRandomEmbedding(256),
        );

        await store.addChunks([chunk2]);

        // Should still be indexed (not duplicated)
        final isIndexed = await store.isIndexed('rec1');
        expect(isIndexed, isTrue);
      });

      test('validates embedding dimensions', () {
        expect(
          () => IndexedChunk(
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Test',
            embedding: [1.0, 2.0, 3.0], // Wrong dimension
          ),
          throwsArgumentError,
        );
      });

      test('handles empty chunk list', () async {
        await store.addChunks([]);
        final ids = await store.getIndexedRecordingIds();
        expect(ids, isEmpty);
      });
    });

    group('Removing Chunks', () {
      test('removes chunks successfully', () async {
        final chunk = IndexedChunk(
          recordingId: 'rec1',
          field: 'transcript',
          chunkIndex: 0,
          chunkText: 'Test chunk',
          embedding: _generateRandomEmbedding(256),
        );

        await store.addChunks([chunk]);
        expect(await store.isIndexed('rec1'), isTrue);

        final removed = await store.removeChunks('rec1');
        expect(removed, isTrue);
        expect(await store.isIndexed('rec1'), isFalse);
      });

      test('returns false when removing non-existent chunks', () async {
        final removed = await store.removeChunks('non_existent');
        expect(removed, isFalse);
      });

      test('removes only specified recording chunks', () async {
        final chunks = [
          IndexedChunk(
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 1',
            embedding: _generateRandomEmbedding(256),
          ),
          IndexedChunk(
            recordingId: 'rec2',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 2',
            embedding: _generateRandomEmbedding(256),
          ),
        ];

        await store.addChunks(chunks);

        await store.removeChunks('rec1');

        expect(await store.isIndexed('rec1'), isFalse);
        expect(await store.isIndexed('rec2'), isTrue);
      });
    });

    group('Manifest Management', () {
      test('updates manifest successfully', () async {
        await store.updateManifest('rec1', 'hash123', 5);

        final hash = await store.getContentHash('rec1');
        expect(hash, equals('hash123'));
      });

      test('returns null for non-existent manifest', () async {
        final hash = await store.getContentHash('non_existent');
        expect(hash, isNull);
      });

      test('updates existing manifest entry', () async {
        await store.updateManifest('rec1', 'hash1', 5);
        await store.updateManifest('rec1', 'hash2', 10);

        final hash = await store.getContentHash('rec1');
        expect(hash, equals('hash2'));
      });

      test('removes manifest when removing chunks', () async {
        final chunk = IndexedChunk(
          recordingId: 'rec1',
          field: 'transcript',
          chunkIndex: 0,
          chunkText: 'Test',
          embedding: _generateRandomEmbedding(256),
        );

        await store.addChunks([chunk]);
        await store.updateManifest('rec1', 'hash123', 1);

        await store.removeChunks('rec1');

        final hash = await store.getContentHash('rec1');
        expect(hash, isNull);
      });
    });

    group('Vector Search', () {
      test('finds exact match with score 1.0', () async {
        final embedding = _generateRandomEmbedding(256);
        final chunk = IndexedChunk(
          recordingId: 'rec1',
          field: 'transcript',
          chunkIndex: 0,
          chunkText: 'Test chunk',
          embedding: embedding,
        );

        await store.addChunks([chunk]);

        final results = await store.search(embedding);

        expect(results.length, equals(1));
        expect(results.first.score, closeTo(1.0, 0.01));
        expect(results.first.recordingId, equals('rec1'));
        expect(results.first.chunkText, equals('Test chunk'));
      });

      test('returns results sorted by similarity', () async {
        final queryEmbedding = _generateRandomEmbedding(256);

        // Create a very similar embedding (high score)
        final similarEmbedding = queryEmbedding.map((v) => v + 0.01).toList();

        // Create a less similar embedding (lower score)
        final lessSimularEmbedding = _generateRandomEmbedding(256);

        final chunks = [
          IndexedChunk(
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Less similar',
            embedding: lessSimularEmbedding,
          ),
          IndexedChunk(
            recordingId: 'rec2',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'More similar',
            embedding: similarEmbedding,
          ),
        ];

        await store.addChunks(chunks);

        final results = await store.search(queryEmbedding);

        expect(results.length, equals(2));
        // First result should be more similar
        expect(results[0].score, greaterThan(results[1].score));
        expect(results[0].chunkText, equals('More similar'));
      });

      test('respects limit parameter', () async {
        final chunks = List.generate(
          10,
          (i) => IndexedChunk(
            recordingId: 'rec$i',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk $i',
            embedding: _generateRandomEmbedding(256),
          ),
        );

        await store.addChunks(chunks);

        final results = await store.search(
          _generateRandomEmbedding(256),
          limit: 5,
        );

        expect(results.length, equals(5));
      });

      test('filters by minimum score', () async {
        final queryEmbedding = _generateRandomEmbedding(256);

        final chunks = List.generate(
          5,
          (i) => IndexedChunk(
            recordingId: 'rec$i',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk $i',
            embedding: _generateRandomEmbedding(256),
          ),
        );

        await store.addChunks(chunks);

        final results = await store.search(
          queryEmbedding,
          minScore: 0.5,
        );

        // All results should have score >= 0.5
        for (final result in results) {
          expect(result.score, greaterThanOrEqualTo(0.5));
        }
      });

      test('returns empty list when no chunks exist', () async {
        final results = await store.search(_generateRandomEmbedding(256));
        expect(results, isEmpty);
      });

      test('handles multiple fields correctly', () async {
        final chunks = [
          IndexedChunk(
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Transcript chunk',
            embedding: _generateRandomEmbedding(256),
          ),
          IndexedChunk(
            recordingId: 'rec1',
            field: 'summary',
            chunkIndex: 0,
            chunkText: 'Summary chunk',
            embedding: _generateRandomEmbedding(256),
          ),
        ];

        await store.addChunks(chunks);

        final results = await store.search(_generateRandomEmbedding(256));

        expect(results.length, equals(2));
        final fields = results.map((r) => r.field).toSet();
        expect(fields, containsAll(['transcript', 'summary']));
      });
    });

    group('Statistics', () {
      test('returns correct stats for empty store', () async {
        final stats = await store.getStats();

        expect(stats['totalChunks'], equals(0));
        expect(stats['totalRecordings'], equals(0));
        expect(stats['totalSize'], greaterThan(0)); // DB file exists
      });

      test('returns correct stats after adding chunks', () async {
        final chunks = [
          IndexedChunk(
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 1',
            embedding: _generateRandomEmbedding(256),
          ),
          IndexedChunk(
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 1,
            chunkText: 'Chunk 2',
            embedding: _generateRandomEmbedding(256),
          ),
          IndexedChunk(
            recordingId: 'rec2',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 3',
            embedding: _generateRandomEmbedding(256),
          ),
        ];

        await store.addChunks(chunks);

        final stats = await store.getStats();

        expect(stats['totalChunks'], equals(3));
        expect(stats['totalRecordings'], equals(2));
        expect(stats['totalSize'], greaterThan(0));
      });
    });

    group('Indexed Recording IDs', () {
      test('returns empty list when no chunks exist', () async {
        final ids = await store.getIndexedRecordingIds();
        expect(ids, isEmpty);
      });

      test('returns unique recording IDs', () async {
        final chunks = [
          IndexedChunk(
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 1',
            embedding: _generateRandomEmbedding(256),
          ),
          IndexedChunk(
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 1,
            chunkText: 'Chunk 2',
            embedding: _generateRandomEmbedding(256),
          ),
          IndexedChunk(
            recordingId: 'rec2',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 3',
            embedding: _generateRandomEmbedding(256),
          ),
        ];

        await store.addChunks(chunks);

        final ids = await store.getIndexedRecordingIds();

        expect(ids.length, equals(2));
        expect(ids, containsAll(['rec1', 'rec2']));
      });

      test('returns sorted IDs', () async {
        final chunks = [
          IndexedChunk(
            recordingId: 'rec3',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 3',
            embedding: _generateRandomEmbedding(256),
          ),
          IndexedChunk(
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 1',
            embedding: _generateRandomEmbedding(256),
          ),
          IndexedChunk(
            recordingId: 'rec2',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 2',
            embedding: _generateRandomEmbedding(256),
          ),
        ];

        await store.addChunks(chunks);

        final ids = await store.getIndexedRecordingIds();

        expect(ids, equals(['rec1', 'rec2', 'rec3']));
      });
    });

    group('Clear Operation', () {
      test('clears all data', () async {
        final chunks = List.generate(
          5,
          (i) => IndexedChunk(
            recordingId: 'rec$i',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk $i',
            embedding: _generateRandomEmbedding(256),
          ),
        );

        await store.addChunks(chunks);
        await store.updateManifest('rec0', 'hash123', 1);

        await store.clear();

        final ids = await store.getIndexedRecordingIds();
        final hash = await store.getContentHash('rec0');

        expect(ids, isEmpty);
        expect(hash, isNull);
      });
    });

    group('Content Hash Utility', () {
      test('generates consistent hashes', () {
        final hash1 = SqliteVectorStore.computeContentHash('test content');
        final hash2 = SqliteVectorStore.computeContentHash('test content');

        expect(hash1, equals(hash2));
      });

      test('generates different hashes for different content', () {
        final hash1 = SqliteVectorStore.computeContentHash('content 1');
        final hash2 = SqliteVectorStore.computeContentHash('content 2');

        expect(hash1, isNot(equals(hash2)));
      });

      test('generates deterministic SHA-256 hash', () {
        final hash = SqliteVectorStore.computeContentHash('test');
        // SHA-256 hash should be 64 hex characters
        expect(hash.length, equals(64));
      });
    });

    group('Performance', () {
      test('handles 1000 chunks efficiently', () async {
        final chunks = List.generate(
          1000,
          (i) => IndexedChunk(
            recordingId: 'rec${i % 100}', // 100 recordings, 10 chunks each
            field: 'transcript',
            chunkIndex: i ~/ 100,
            chunkText: 'Chunk $i with some test content',
            embedding: _generateRandomEmbedding(256),
          ),
        );

        final startAdd = DateTime.now();
        await store.addChunks(chunks);
        final addDuration = DateTime.now().difference(startAdd);

        print('Added 1000 chunks in ${addDuration.inMilliseconds}ms');

        final startSearch = DateTime.now();
        final results = await store.search(
          _generateRandomEmbedding(256),
          limit: 20,
        );
        final searchDuration = DateTime.now().difference(startSearch);

        print('Searched 1000 chunks in ${searchDuration.inMilliseconds}ms');

        expect(results.length, equals(20));
        expect(addDuration.inMilliseconds, lessThan(5000)); // < 5s
        expect(searchDuration.inMilliseconds, lessThan(500)); // < 500ms
      });
    });
  });
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Generate a random normalized embedding vector
List<double> _generateRandomEmbedding(int dimensions) {
  final random = math.Random();
  final embedding = List.generate(dimensions, (_) => random.nextDouble() - 0.5);

  // Normalize to unit length
  double norm = 0.0;
  for (final val in embedding) {
    norm += val * val;
  }
  norm = math.sqrt(norm);

  return embedding.map((val) => val / norm).toList();
}
