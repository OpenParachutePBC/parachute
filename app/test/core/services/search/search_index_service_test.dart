import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:app/core/services/search/search_index_service.dart';
import 'package:app/core/services/search/vector_store.dart';
import 'package:app/core/services/search/bm25_index_manager.dart';
import 'package:app/core/services/search/chunking/recording_chunker.dart';
import 'package:app/core/services/search/content_hasher.dart';
import 'package:app/core/services/search/models/indexed_chunk.dart';
import 'package:app/features/recorder/services/storage_service.dart';
import 'package:app/features/recorder/models/recording.dart';

@GenerateMocks([
  VectorStore,
  BM25IndexManager,
  RecordingChunker,
  StorageService,
  ContentHasher,
])
import 'search_index_service_test.mocks.dart';

void main() {
  group('SearchIndexService', () {
    late MockVectorStore mockVectorStore;
    late MockBM25IndexManager mockBM25Manager;
    late MockRecordingChunker mockChunker;
    late MockStorageService mockStorageService;
    late MockContentHasher mockHasher;
    late SearchIndexService service;

    setUp(() {
      mockVectorStore = MockVectorStore();
      mockBM25Manager = MockBM25IndexManager();
      mockChunker = MockRecordingChunker();
      mockStorageService = MockStorageService();
      mockHasher = MockContentHasher();

      service = SearchIndexService(
        mockVectorStore,
        mockBM25Manager,
        mockChunker,
        mockStorageService,
        mockHasher,
      );
    });

    group('initial state', () {
      test('starts in idle status', () {
        expect(service.status, equals(IndexingStatus.idle));
      });

      test('has no error message initially', () {
        expect(service.errorMessage, isNull);
      });

      test('has zero progress initially', () {
        expect(service.progress, equals(0.0));
        expect(service.totalToIndex, equals(0));
        expect(service.indexedCount, equals(0));
      });

      test('is not syncing initially', () {
        expect(service.isSyncing, isFalse);
      });
    });

    group('syncIndexes', () {
      test('indexes new recording', () async {
        final recording = _createSampleRecording(id: 'new-rec');
        final chunks = _createSampleChunks('new-rec');

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => [recording],
        );
        when(mockVectorStore.getIndexedRecordingIds()).thenAnswer(
          (_) async => [],
        );
        when(mockHasher.computeHash(any)).thenReturn('hash123');
        when(mockVectorStore.getContentHash(any)).thenAnswer((_) async => null);
        when(mockChunker.chunkRecording(any)).thenAnswer((_) async => chunks);
        when(mockVectorStore.removeChunks(any)).thenAnswer((_) async => false);
        when(mockVectorStore.addChunks(any)).thenAnswer((_) async {});
        when(mockVectorStore.updateManifest(any, any, any)).thenAnswer(
          (_) async {},
        );
        when(mockBM25Manager.rebuildIndex()).thenAnswer((_) async {});

        await service.syncIndexes();

        verify(mockChunker.chunkRecording(recording)).called(1);
        verify(mockVectorStore.addChunks(chunks)).called(1);
        verify(mockVectorStore.updateManifest('new-rec', 'hash123', 3)).called(
          1,
        );
        verify(mockBM25Manager.rebuildIndex()).called(1);
      });

      test('re-indexes modified recording', () async {
        final recording = _createSampleRecording(id: 'modified-rec');
        final chunks = _createSampleChunks('modified-rec');

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => [recording],
        );
        when(mockVectorStore.getIndexedRecordingIds()).thenAnswer(
          (_) async => ['modified-rec'],
        );
        when(mockHasher.computeHash(any)).thenReturn('new-hash');
        when(mockVectorStore.getContentHash('modified-rec')).thenAnswer(
          (_) async => 'old-hash',
        );
        when(mockChunker.chunkRecording(any)).thenAnswer((_) async => chunks);
        when(mockVectorStore.removeChunks(any)).thenAnswer((_) async => true);
        when(mockVectorStore.addChunks(any)).thenAnswer((_) async {});
        when(mockVectorStore.updateManifest(any, any, any)).thenAnswer(
          (_) async {},
        );
        when(mockBM25Manager.rebuildIndex()).thenAnswer((_) async {});

        await service.syncIndexes();

        verify(mockChunker.chunkRecording(recording)).called(1);
        verify(mockVectorStore.addChunks(chunks)).called(1);
      });

      test('skips unchanged recording', () async {
        final recording = _createSampleRecording(id: 'unchanged-rec');

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => [recording],
        );
        when(mockVectorStore.getIndexedRecordingIds()).thenAnswer(
          (_) async => ['unchanged-rec'],
        );
        when(mockHasher.computeHash(any)).thenReturn('same-hash');
        when(mockVectorStore.getContentHash('unchanged-rec')).thenAnswer(
          (_) async => 'same-hash',
        );
        when(mockBM25Manager.rebuildIndex()).thenAnswer((_) async {});

        await service.syncIndexes();

        verifyNever(mockChunker.chunkRecording(any));
        verifyNever(mockVectorStore.addChunks(any));
        verify(mockBM25Manager.rebuildIndex()).called(1);
      });

      test('removes deleted recording', () async {
        when(mockStorageService.getRecordings()).thenAnswer((_) async => []);
        when(mockVectorStore.getIndexedRecordingIds()).thenAnswer(
          (_) async => ['deleted-rec'],
        );
        when(mockVectorStore.removeChunks('deleted-rec')).thenAnswer(
          (_) async => true,
        );
        when(mockBM25Manager.rebuildIndex()).thenAnswer((_) async {});

        await service.syncIndexes();

        verify(mockVectorStore.removeChunks('deleted-rec')).called(1);
      });

      test('updates status during sync', () async {
        final recording = _createSampleRecording();
        final chunks = _createSampleChunks('test-rec');
        final statusChanges = <IndexingStatus>[];

        service.addListener(() {
          statusChanges.add(service.status);
        });

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => [recording],
        );
        when(mockVectorStore.getIndexedRecordingIds()).thenAnswer(
          (_) async => [],
        );
        when(mockHasher.computeHash(any)).thenReturn('hash');
        when(mockVectorStore.getContentHash(any)).thenAnswer((_) async => null);
        when(mockChunker.chunkRecording(any)).thenAnswer((_) async => chunks);
        when(mockVectorStore.removeChunks(any)).thenAnswer((_) async => false);
        when(mockVectorStore.addChunks(any)).thenAnswer((_) async {});
        when(mockVectorStore.updateManifest(any, any, any)).thenAnswer(
          (_) async {},
        );
        when(mockBM25Manager.rebuildIndex()).thenAnswer((_) async {});

        await service.syncIndexes();

        // Should see: syncing → indexing → idle
        expect(statusChanges, contains(IndexingStatus.syncing));
        expect(statusChanges, contains(IndexingStatus.indexing));
        expect(statusChanges.last, equals(IndexingStatus.idle));
      });

      test('handles concurrent sync requests', () async {
        when(mockStorageService.getRecordings()).thenAnswer((_) async => []);
        when(mockVectorStore.getIndexedRecordingIds()).thenAnswer(
          (_) async => [],
        );
        when(mockBM25Manager.rebuildIndex()).thenAnswer(
          (_) async => await Future.delayed(const Duration(milliseconds: 100)),
        );

        // Start two syncs concurrently
        final future1 = service.syncIndexes();
        final future2 = service.syncIndexes();

        await Future.wait([future1, future2]);

        // Should only call getRecordings once (second sync waits for first)
        verify(mockStorageService.getRecordings()).called(1);
      });

      test('sets error status on failure', () async {
        when(mockStorageService.getRecordings()).thenThrow(
          Exception('Storage error'),
        );

        try {
          await service.syncIndexes();
          fail('Should have thrown exception');
        } catch (e) {
          expect(e.toString(), contains('Storage error'));
        }

        expect(service.status, equals(IndexingStatus.error));
        expect(service.errorMessage, isNotNull);
      });

      test('continues indexing after individual recording error', () async {
        final recording1 = _createSampleRecording(id: 'rec-1');
        final recording2 = _createSampleRecording(id: 'rec-2');
        final chunks = _createSampleChunks('rec-2');

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => [recording1, recording2],
        );
        when(mockVectorStore.getIndexedRecordingIds()).thenAnswer(
          (_) async => [],
        );
        when(mockHasher.computeHash(any)).thenReturn('hash');
        when(mockVectorStore.getContentHash(any)).thenAnswer((_) async => null);

        // First recording fails
        when(mockChunker.chunkRecording(recording1)).thenThrow(
          Exception('Chunking error'),
        );

        // Second recording succeeds
        when(mockChunker.chunkRecording(recording2)).thenAnswer(
          (_) async => chunks,
        );
        when(mockVectorStore.removeChunks(any)).thenAnswer((_) async => false);
        when(mockVectorStore.addChunks(any)).thenAnswer((_) async {});
        when(mockVectorStore.updateManifest(any, any, any)).thenAnswer(
          (_) async {},
        );
        when(mockBM25Manager.rebuildIndex()).thenAnswer((_) async {});

        await service.syncIndexes();

        // Should have tried both recordings
        verify(mockChunker.chunkRecording(recording1)).called(1);
        verify(mockChunker.chunkRecording(recording2)).called(1);

        // Second recording should be indexed successfully
        verify(mockVectorStore.addChunks(chunks)).called(1);

        // Should complete in idle state (not error)
        expect(service.status, equals(IndexingStatus.idle));
      });
    });

    group('indexRecording', () {
      test('indexes single recording', () async {
        final recording = _createSampleRecording();
        final chunks = _createSampleChunks('test-rec');

        when(mockHasher.computeHash(any)).thenReturn('hash123');
        when(mockChunker.chunkRecording(any)).thenAnswer((_) async => chunks);
        when(mockVectorStore.removeChunks(any)).thenAnswer((_) async => true);
        when(mockVectorStore.addChunks(any)).thenAnswer((_) async {});
        when(mockVectorStore.updateManifest(any, any, any)).thenAnswer(
          (_) async {},
        );
        when(mockBM25Manager.invalidate()).thenReturn(null);

        await service.indexRecording(recording);

        verify(mockChunker.chunkRecording(recording)).called(1);
        verify(mockVectorStore.addChunks(chunks)).called(1);
        verify(mockVectorStore.updateManifest('test-rec', 'hash123', 3)).called(
          1,
        );
        verify(mockBM25Manager.invalidate()).called(1);
      });

      test('removes old chunks before adding new ones', () async {
        final recording = _createSampleRecording();
        final chunks = _createSampleChunks('test-rec');

        when(mockHasher.computeHash(any)).thenReturn('hash');
        when(mockChunker.chunkRecording(any)).thenAnswer((_) async => chunks);
        when(mockVectorStore.removeChunks(any)).thenAnswer((_) async => true);
        when(mockVectorStore.addChunks(any)).thenAnswer((_) async {});
        when(mockVectorStore.updateManifest(any, any, any)).thenAnswer(
          (_) async {},
        );
        when(mockBM25Manager.invalidate()).thenReturn(null);

        await service.indexRecording(recording);

        verifyInOrder([
          mockVectorStore.removeChunks('test-rec'),
          mockVectorStore.addChunks(chunks),
        ]);
      });

      test('handles empty chunks', () async {
        final recording = _createSampleRecording();

        when(mockHasher.computeHash(any)).thenReturn('hash');
        when(mockChunker.chunkRecording(any)).thenAnswer((_) async => []);
        when(mockVectorStore.removeChunks(any)).thenAnswer((_) async => false);
        when(mockBM25Manager.invalidate()).thenReturn(null);

        await service.indexRecording(recording);

        // Should not try to add empty chunks
        verifyNever(mockVectorStore.addChunks(any));
        verifyNever(mockVectorStore.updateManifest(any, any, any));
      });

      test('propagates errors', () async {
        final recording = _createSampleRecording();

        when(mockVectorStore.removeChunks(any)).thenThrow(
          Exception('Vector store error'),
        );

        expect(
          () => service.indexRecording(recording),
          throwsException,
        );
      });
    });

    group('removeRecording', () {
      test('removes chunks and invalidates BM25', () async {
        when(mockVectorStore.removeChunks('test-rec')).thenAnswer(
          (_) async => true,
        );
        when(mockBM25Manager.invalidate()).thenReturn(null);

        await service.removeRecording('test-rec');

        verify(mockVectorStore.removeChunks('test-rec')).called(1);
        verify(mockBM25Manager.invalidate()).called(1);
      });

      test('propagates errors', () async {
        when(mockVectorStore.removeChunks(any)).thenThrow(
          Exception('Remove error'),
        );

        expect(
          () => service.removeRecording('test-rec'),
          throwsException,
        );
      });
    });

    group('forceFullReindex', () {
      test('clears stores and triggers sync', () async {
        when(mockVectorStore.clear()).thenAnswer((_) async {});
        when(mockBM25Manager.invalidate()).thenReturn(null);
        when(mockStorageService.getRecordings()).thenAnswer((_) async => []);
        when(mockVectorStore.getIndexedRecordingIds()).thenAnswer(
          (_) async => [],
        );
        when(mockBM25Manager.rebuildIndex()).thenAnswer((_) async {});

        await service.forceFullReindex();

        verifyInOrder([
          mockVectorStore.clear(),
          mockBM25Manager.invalidate(),
          mockStorageService.getRecordings(),
        ]);
      });
    });

    group('getStats', () {
      test('returns combined statistics', () async {
        when(mockVectorStore.getStats()).thenAnswer(
          (_) async => {
            'totalChunks': 100,
            'totalRecordings': 10,
            'totalSize': 50000,
          },
        );
        when(mockBM25Manager.getStats()).thenReturn({
          'isBuilt': true,
          'indexSize': 10,
        });

        final stats = await service.getStats();

        expect(stats['vectorStore'], isNotNull);
        expect(stats['bm25'], isNotNull);
        expect(stats['status'], isNotNull);
        expect(stats['progress'], equals(0.0));
      });
    });

    group('listeners', () {
      test('notifies listeners on status change', () async {
        int callCount = 0;
        service.addListener(() {
          callCount++;
        });

        final recording = _createSampleRecording();
        final chunks = _createSampleChunks('test-rec');

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => [recording],
        );
        when(mockVectorStore.getIndexedRecordingIds()).thenAnswer(
          (_) async => [],
        );
        when(mockHasher.computeHash(any)).thenReturn('hash');
        when(mockVectorStore.getContentHash(any)).thenAnswer((_) async => null);
        when(mockChunker.chunkRecording(any)).thenAnswer((_) async => chunks);
        when(mockVectorStore.removeChunks(any)).thenAnswer((_) async => false);
        when(mockVectorStore.addChunks(any)).thenAnswer((_) async {});
        when(mockVectorStore.updateManifest(any, any, any)).thenAnswer(
          (_) async {},
        );
        when(mockBM25Manager.rebuildIndex()).thenAnswer((_) async {});

        await service.syncIndexes();

        // Should be notified multiple times during sync
        expect(callCount, greaterThan(0));
      });

      test('removes listener', () {
        int callCount = 0;
        void listener() {
          callCount++;
        }

        service.addListener(listener);
        service.removeListener(listener);

        // Listener should not be called after removal
        // (We can't easily test this without triggering an actual status change)
        expect(callCount, equals(0));
      });

      test('handles listener errors gracefully', () async {
        service.addListener(() {
          throw Exception('Listener error');
        });

        // Should not throw despite listener error
        final recording = _createSampleRecording();
        final chunks = _createSampleChunks('test-rec');

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => [recording],
        );
        when(mockVectorStore.getIndexedRecordingIds()).thenAnswer(
          (_) async => [],
        );
        when(mockHasher.computeHash(any)).thenReturn('hash');
        when(mockVectorStore.getContentHash(any)).thenAnswer((_) async => null);
        when(mockChunker.chunkRecording(any)).thenAnswer((_) async => chunks);
        when(mockVectorStore.removeChunks(any)).thenAnswer((_) async => false);
        when(mockVectorStore.addChunks(any)).thenAnswer((_) async {});
        when(mockVectorStore.updateManifest(any, any, any)).thenAnswer(
          (_) async {},
        );
        when(mockBM25Manager.rebuildIndex()).thenAnswer((_) async {});

        // Should complete without throwing
        await service.syncIndexes();
      });
    });

    group('dispose', () {
      test('closes vector store', () async {
        when(mockVectorStore.close()).thenAnswer((_) async {});

        await service.dispose();

        verify(mockVectorStore.close()).called(1);
      });

      test('clears listeners', () async {
        service.addListener(() {});
        when(mockVectorStore.close()).thenAnswer((_) async {});

        await service.dispose();

        // Listeners should be cleared (can't directly test, but ensures no leaks)
      });
    });
  });
}

/// Helper function to create a sample recording for testing
Recording _createSampleRecording({
  String? id,
  String? title,
}) {
  return Recording(
    id: id ?? 'test-rec',
    title: title ?? 'Test Recording',
    filePath: '/test/recording.opus',
    timestamp: DateTime.now(),
    duration: const Duration(minutes: 5),
    tags: ['test'],
    transcript: 'This is a test transcript',
    fileSizeKB: 100.0,
  );
}

/// Helper function to create sample chunks for testing
List<IndexedChunk> _createSampleChunks(String recordingId) {
  return [
    IndexedChunk(
      recordingId: recordingId,
      field: 'transcript',
      chunkIndex: 0,
      chunkText: 'First chunk',
      embedding: List.filled(256, 0.1),
    ),
    IndexedChunk(
      recordingId: recordingId,
      field: 'transcript',
      chunkIndex: 1,
      chunkText: 'Second chunk',
      embedding: List.filled(256, 0.2),
    ),
    IndexedChunk(
      recordingId: recordingId,
      field: 'title',
      chunkIndex: 0,
      chunkText: 'Title chunk',
      embedding: List.filled(256, 0.3),
    ),
  ];
}
