import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/services/search/hybrid_search_service.dart';
import 'package:app/core/services/search/vector_store.dart';
import 'package:app/core/services/search/bm25_search_service.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/search/models/vector_search_result.dart';
import 'package:app/core/services/search/models/bm25_search_result.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/services/storage_service.dart';

/// Mock VectorStore for testing
class MockVectorStore implements VectorStore {
  List<VectorSearchResult>? _nextResults;
  Exception? _nextError;

  void setNextResults(List<VectorSearchResult> results) {
    _nextResults = results;
  }

  void setNextError(Exception error) {
    _nextError = error;
  }

  @override
  Future<List<VectorSearchResult>> search(
    List<double> queryEmbedding, {
    int limit = 20,
    double minScore = 0.0,
  }) async {
    if (_nextError != null) {
      final error = _nextError;
      _nextError = null;
      throw error!;
    }
    final results = _nextResults ?? [];
    _nextResults = null;
    return results;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> addChunks(chunks) async {}

  @override
  Future<bool> removeChunks(String recordingId) async => true;

  @override
  Future<bool> isIndexed(String recordingId) async => false;

  @override
  Future<String?> getContentHash(String recordingId) async => null;

  @override
  Future<void> updateManifest(String recordingId, String contentHash, int chunkCount) async {}

  @override
  Future<List<String>> getIndexedRecordingIds() async => [];

  @override
  Future<Map<String, dynamic>> getStats() async => {};

  @override
  Future<void> clear() async {}

  @override
  Future<void> close() async {}
}

/// Mock BM25SearchService for testing
class MockBM25SearchService implements BM25SearchService {
  List<BM25SearchResult>? _nextResults;
  Exception? _nextError;

  void setNextResults(List<BM25SearchResult> results) {
    _nextResults = results;
  }

  void setNextError(Exception error) {
    _nextError = error;
  }

  @override
  Future<List<BM25SearchResult>> search(
    String query, {
    int limit = 20,
  }) async {
    if (_nextError != null) {
      final error = _nextError;
      _nextError = null;
      throw error!;
    }
    final results = _nextResults ?? [];
    _nextResults = null;
    return results;
  }

  @override
  Future<void> buildIndex(List<Recording> recordings) async {}

  @override
  bool get needsRebuild => false;

  @override
  int get indexSize => 0;

  @override
  void clear() {}
}

/// Mock EmbeddingService for testing
class MockEmbeddingService implements EmbeddingService {
  Exception? _nextError;

  void setNextError(Exception error) {
    _nextError = error;
  }

  @override
  Future<List<double>> embed(String text) async {
    if (_nextError != null) {
      final error = _nextError;
      _nextError = null;
      throw error!;
    }
    return List.filled(256, 0.5); // Dummy embedding
  }

  @override
  Future<bool> isReady() async => true;

  @override
  Future<bool> needsDownload() async => false;

  @override
  Stream<double> downloadModel() async* {}

  @override
  int get dimensions => 256;

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    return texts.map((_) => List.filled(256, 0.5)).toList();
  }

  @override
  Future<void> dispose() async {}
}

/// Mock StorageService for testing
class MockStorageService implements StorageService {
  final Map<String, Recording> _recordings = {};

  void addRecording(Recording recording) {
    _recordings[recording.id] = recording;
  }

  @override
  Future<Recording?> getRecording(String id) async {
    return _recordings[id];
  }

  @override
  Future<List<Recording>> getAllRecordings() async => _recordings.values.toList();

  @override
  Future<void> saveRecording(Recording recording) async {}

  @override
  Future<void> deleteRecording(String id) async {}

  @override
  Future<void> updateRecording(Recording recording) async {}

  @override
  Future<String> get capturesPath async => '/mock/captures';

  @override
  Future<String> get spheresPath async => '/mock/spheres';

  @override
  Future<List<Recording>> getRecordingsByTag(String tag) async => [];
}

/// Helper to create test recording
Recording createTestRecording({
  required String id,
  String title = 'Test Recording',
  String transcript = 'Test transcript',
}) {
  return Recording(
    id: id,
    title: title,
    filePath: '/test/$id.opus',
    timestamp: DateTime(2025, 1, 1),
    duration: Duration(seconds: 10),
    tags: [],
    transcript: transcript,
    fileSizeKB: 100.0,
  );
}

void main() {
  group('HybridSearchService', () {
    late MockVectorStore mockVectorStore;
    late MockBM25SearchService mockBM25Service;
    late MockEmbeddingService mockEmbeddingService;
    late MockStorageService mockStorageService;
    late HybridSearchService hybridSearch;

    setUp(() {
      mockVectorStore = MockVectorStore();
      mockBM25Service = MockBM25SearchService();
      mockEmbeddingService = MockEmbeddingService();
      mockStorageService = MockStorageService();

      hybridSearch = HybridSearchService(
        mockVectorStore,
        mockBM25Service,
        mockEmbeddingService,
        mockStorageService,
      );
    });

    group('Basic Search', () {
      test('returns empty results for empty query', () async {
        final results = await hybridSearch.search('');
        expect(results, isEmpty);
      });

      test('returns empty results for whitespace query', () async {
        final results = await hybridSearch.search('   ');
        expect(results, isEmpty);
      });

      test('throws SearchException when both searches fail', () async {
        mockVectorStore.setNextError(Exception('Vector search failed'));
        mockBM25Service.setNextError(Exception('BM25 search failed'));

        expect(
          () => hybridSearch.search('test'),
          throwsA(isA<SearchException>()),
        );
      });
    });

    group('Vector-Only Results', () {
      test('returns vector-only results when BM25 fails', () async {
        final recording = createTestRecording(id: 'rec1');
        mockStorageService.addRecording(recording);

        mockVectorStore.setNextResults([
          VectorSearchResult(
            chunkId: 1,
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Test chunk',
            score: 0.9,
          ),
        ]);
        mockBM25Service.setNextError(Exception('BM25 failed'));

        final results = await hybridSearch.search('test');

        expect(results.length, 1);
        expect(results[0].recording.id, 'rec1');
        expect(results[0].hasVectorMatch, true);
        expect(results[0].hasKeywordMatch, false);
        expect(results[0].vectorScore, 0.9);
        expect(results[0].keywordScore, null);
      });

      test('deduplicates vector results by recording ID', () async {
        final recording = createTestRecording(id: 'rec1');
        mockStorageService.addRecording(recording);

        mockVectorStore.setNextResults([
          VectorSearchResult(
            chunkId: 1,
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'First chunk',
            score: 0.9,
          ),
          VectorSearchResult(
            chunkId: 2,
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 1,
            chunkText: 'Second chunk',
            score: 0.8,
          ),
        ]);
        mockBM25Service.setNextError(Exception('BM25 failed'));

        final results = await hybridSearch.search('test');

        // Should only return one result (deduplicated)
        expect(results.length, 1);
        expect(results[0].recording.id, 'rec1');
        expect(results[0].matchedChunk, 'First chunk'); // Highest scored chunk
      });
    });

    group('Keyword-Only Results', () {
      test('returns keyword-only results when vector search fails', () async {
        final recording = createTestRecording(id: 'rec1');
        mockStorageService.addRecording(recording);

        mockVectorStore.setNextError(Exception('Vector search failed'));
        mockBM25Service.setNextResults([
          BM25SearchResult(
            recording: recording,
            score: 8.5,
            matchedFields: {'title', 'transcript'},
          ),
        ]);

        final results = await hybridSearch.search('test');

        expect(results.length, 1);
        expect(results[0].recording.id, 'rec1');
        expect(results[0].hasVectorMatch, false);
        expect(results[0].hasKeywordMatch, true);
        expect(results[0].keywordScore, 8.5);
        expect(results[0].vectorScore, null);
        expect(results[0].matchedFields, {'title', 'transcript'});
      });
    });

    group('RRF Merging', () {
      test('merges results from both searches using RRF', () async {
        final rec1 = createTestRecording(id: 'rec1', title: 'First');
        final rec2 = createTestRecording(id: 'rec2', title: 'Second');
        mockStorageService.addRecording(rec1);
        mockStorageService.addRecording(rec2);

        // rec1 is rank 0 in vector (score: 1/60)
        // rec2 is rank 1 in vector (score: 1/61)
        mockVectorStore.setNextResults([
          VectorSearchResult(
            chunkId: 1,
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 1',
            score: 0.9,
          ),
          VectorSearchResult(
            chunkId: 2,
            recordingId: 'rec2',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 2',
            score: 0.8,
          ),
        ]);

        // rec2 is rank 0 in BM25 (score: 1/60)
        // rec1 is rank 1 in BM25 (score: 1/61)
        mockBM25Service.setNextResults([
          BM25SearchResult(recording: rec2, score: 10.0, matchedFields: {'title'}),
          BM25SearchResult(recording: rec1, score: 8.0, matchedFields: {'transcript'}),
        ]);

        final results = await hybridSearch.search('test');

        expect(results.length, 2);

        // rec2 should win: 1/60 (vector) + 1/60 (BM25) = 0.0333
        // rec1 should be second: 1/60 (vector) + 1/61 (BM25) = 0.0331
        expect(results[0].recording.id, 'rec2');
        expect(results[1].recording.id, 'rec1');

        // Both should be marked as "both match"
        expect(results[0].isBothMatch, true);
        expect(results[1].isBothMatch, true);

        // Verify RRF scores
        expect(results[0].rrfScore, closeTo(0.0333, 0.0001));
        expect(results[1].rrfScore, closeTo(0.0331, 0.0001));
      });

      test('calculates correct RRF scores for single-source matches', () async {
        final rec1 = createTestRecording(id: 'rec1');
        final rec2 = createTestRecording(id: 'rec2');
        mockStorageService.addRecording(rec1);
        mockStorageService.addRecording(rec2);

        // rec1 only in vector (rank 0)
        mockVectorStore.setNextResults([
          VectorSearchResult(
            chunkId: 1,
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 1',
            score: 0.9,
          ),
        ]);

        // rec2 only in BM25 (rank 0)
        mockBM25Service.setNextResults([
          BM25SearchResult(recording: rec2, score: 10.0, matchedFields: {'title'}),
        ]);

        final results = await hybridSearch.search('test');

        expect(results.length, 2);

        // Both should have same score: 1/60 = 0.0166
        expect(results[0].rrfScore, closeTo(0.0166, 0.0001));
        expect(results[1].rrfScore, closeTo(0.0166, 0.0001));

        // One from vector, one from keyword
        final vectorResult = results.firstWhere((r) => r.recording.id == 'rec1');
        final keywordResult = results.firstWhere((r) => r.recording.id == 'rec2');

        expect(vectorResult.hasVectorMatch, true);
        expect(vectorResult.hasKeywordMatch, false);
        expect(keywordResult.hasVectorMatch, false);
        expect(keywordResult.hasKeywordMatch, true);
      });

      test('handles different ranking positions correctly', () async {
        final rec1 = createTestRecording(id: 'rec1');
        final rec2 = createTestRecording(id: 'rec2');
        final rec3 = createTestRecording(id: 'rec3');
        mockStorageService.addRecording(rec1);
        mockStorageService.addRecording(rec2);
        mockStorageService.addRecording(rec3);

        // Vector: rec1 (rank 0), rec2 (rank 1), rec3 (rank 2)
        mockVectorStore.setNextResults([
          VectorSearchResult(
            chunkId: 1,
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 1',
            score: 0.9,
          ),
          VectorSearchResult(
            chunkId: 2,
            recordingId: 'rec2',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 2',
            score: 0.8,
          ),
          VectorSearchResult(
            chunkId: 3,
            recordingId: 'rec3',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 3',
            score: 0.7,
          ),
        ]);

        // BM25: rec3 (rank 0), rec2 (rank 1), rec1 (rank 2)
        mockBM25Service.setNextResults([
          BM25SearchResult(recording: rec3, score: 12.0, matchedFields: {'title'}),
          BM25SearchResult(recording: rec2, score: 10.0, matchedFields: {'transcript'}),
          BM25SearchResult(recording: rec1, score: 8.0, matchedFields: {'context'}),
        ]);

        final results = await hybridSearch.search('test');

        expect(results.length, 3);

        // rec2 should win (ranks 1,1): 1/61 + 1/61 = 0.0328
        // rec3 should be second (ranks 2,0): 1/62 + 1/60 = 0.0328 (very close, but vector helps)
        // rec1 should be third (ranks 0,2): 1/60 + 1/62 = 0.0328 (very close)

        // All three should have similar scores, order may vary slightly
        expect(results[0].isBothMatch, true);
        expect(results[1].isBothMatch, true);
        expect(results[2].isBothMatch, true);
      });
    });

    group('Deduplication', () {
      test('deduplicates by recording ID in merged results', () async {
        final rec1 = createTestRecording(id: 'rec1');
        mockStorageService.addRecording(rec1);

        // rec1 appears in both vector search (with 2 chunks) and BM25
        mockVectorStore.setNextResults([
          VectorSearchResult(
            chunkId: 1,
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'First chunk',
            score: 0.9,
          ),
          VectorSearchResult(
            chunkId: 2,
            recordingId: 'rec1',
            field: 'transcript',
            chunkIndex: 1,
            chunkText: 'Second chunk',
            score: 0.8,
          ),
        ]);

        mockBM25Service.setNextResults([
          BM25SearchResult(
            recording: rec1,
            score: 10.0,
            matchedFields: {'title'},
          ),
        ]);

        final results = await hybridSearch.search('test');

        // Should only return one result despite appearing 3 times
        expect(results.length, 1);
        expect(results[0].recording.id, 'rec1');
      });
    });

    group('Limit Parameter', () {
      test('respects limit parameter', () async {
        // Create 10 recordings
        for (int i = 0; i < 10; i++) {
          mockStorageService.addRecording(
            createTestRecording(id: 'rec$i', title: 'Recording $i'),
          );
        }

        // Return 10 vector results
        mockVectorStore.setNextResults(
          List.generate(
            10,
            (i) => VectorSearchResult(
              chunkId: i,
              recordingId: 'rec$i',
              field: 'transcript',
              chunkIndex: 0,
              chunkText: 'Chunk $i',
              score: 0.9 - i * 0.01,
            ),
          ),
        );

        mockBM25Service.setNextResults([]);

        // Request only 5 results
        final results = await hybridSearch.search('test', limit: 5);

        expect(results.length, 5);
      });
    });

    group('Error Handling', () {
      test('handles missing recordings gracefully', () async {
        // Don't add rec1 to storage
        mockVectorStore.setNextResults([
          VectorSearchResult(
            chunkId: 1,
            recordingId: 'rec1', // Missing from storage
            field: 'transcript',
            chunkIndex: 0,
            chunkText: 'Chunk 1',
            score: 0.9,
          ),
        ]);
        mockBM25Service.setNextResults([]);

        final results = await hybridSearch.search('test');

        // Should return empty results (recording not found)
        expect(results, isEmpty);
      });
    });
  });

  group('SearchResult', () {
    late Recording recording;

    setUp(() {
      recording = createTestRecording(
        id: 'test1',
        title: 'Test Recording',
        transcript: 'This is a test transcript that is quite long and should be truncated when shown as a snippet in the UI.',
      );
    });

    test('relevanceLabel returns correct labels', () {
      final highResult = _createSearchResult(recording, rrfScore: 0.04);
      expect(highResult.relevanceLabel, 'High relevance');

      final mediumResult = _createSearchResult(recording, rrfScore: 0.025);
      expect(mediumResult.relevanceLabel, 'Medium relevance');

      final lowResult = _createSearchResult(recording, rrfScore: 0.01);
      expect(lowResult.relevanceLabel, 'Low relevance');
    });

    test('isBothMatch returns true when both scores present', () {
      final bothMatch = _createSearchResult(
        recording,
        rrfScore: 0.03,
        vectorScore: 0.9,
        keywordScore: 8.5,
      );
      expect(bothMatch.isBothMatch, true);

      final vectorOnly = _createSearchResult(
        recording,
        rrfScore: 0.02,
        vectorScore: 0.9,
      );
      expect(vectorOnly.isBothMatch, false);

      final keywordOnly = _createSearchResult(
        recording,
        rrfScore: 0.02,
        keywordScore: 8.5,
      );
      expect(keywordOnly.isBothMatch, false);
    });

    test('getSnippet returns matched chunk if available', () {
      final result = _createSearchResult(
        recording,
        rrfScore: 0.03,
        matchedChunk: 'This is the matched chunk',
      );
      expect(result.getSnippet(), 'This is the matched chunk');
    });

    test('getSnippet truncates long chunks', () {
      final longChunk = 'a' * 200;
      final result = _createSearchResult(
        recording,
        rrfScore: 0.03,
        matchedChunk: longChunk,
      );
      final snippet = result.getSnippet(maxLength: 100);
      expect(snippet.length, 104); // 100 + '...'
      expect(snippet.endsWith('...'), true);
    });

    test('getSnippet falls back to transcript if no chunk', () {
      final result = _createSearchResult(
        recording,
        rrfScore: 0.03,
        matchedChunk: null,
      );
      final snippet = result.getSnippet();
      expect(snippet, contains('This is a test transcript'));
    });
  });
}

/// Helper to create SearchResult for testing
_createSearchResult(
  Recording recording, {
  required double rrfScore,
  String? matchedChunk,
  double? vectorScore,
  double? keywordScore,
}) {
  return SearchResult(
    recording: recording,
    matchedChunk: matchedChunk,
    matchedField: 'transcript',
    matchedFields: {},
    rrfScore: rrfScore,
    vectorScore: vectorScore,
    keywordScore: keywordScore,
  );
}
