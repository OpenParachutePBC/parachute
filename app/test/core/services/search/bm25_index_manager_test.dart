import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:app/core/services/search/bm25_search_service.dart';
import 'package:app/core/services/search/bm25_index_manager.dart';
import 'package:app/features/recorder/services/storage_service.dart';
import 'package:app/features/recorder/models/recording.dart';

@GenerateMocks([BM25SearchService, StorageService])
import 'bm25_index_manager_test.mocks.dart';

void main() {
  group('BM25IndexManager', () {
    late MockBM25SearchService mockSearchService;
    late MockStorageService mockStorageService;
    late BM25IndexManager manager;

    setUp(() {
      mockSearchService = MockBM25SearchService();
      mockStorageService = MockStorageService();
      manager = BM25IndexManager(mockSearchService, mockStorageService);
    });

    group('ensureIndexReady', () {
      test('builds index if it needs rebuild', () async {
        final recordings = _createSampleRecordings();

        when(mockSearchService.needsRebuild).thenReturn(true);
        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => recordings,
        );
        when(mockSearchService.buildIndex(any)).thenAnswer((_) async {});

        await manager.ensureIndexReady();

        verify(mockSearchService.buildIndex(recordings)).called(1);
      });

      test('does not build index if already ready', () async {
        when(mockSearchService.needsRebuild).thenReturn(false);

        await manager.ensureIndexReady();

        verifyNever(mockStorageService.getRecordings());
        verifyNever(mockSearchService.buildIndex(any));
      });
    });

    group('rebuildIndex', () {
      test('loads recordings and builds index', () async {
        final recordings = _createSampleRecordings();

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => recordings,
        );
        when(mockSearchService.buildIndex(any)).thenAnswer((_) async {});

        await manager.rebuildIndex();

        verify(mockStorageService.getRecordings()).called(1);
        verify(mockSearchService.buildIndex(recordings)).called(1);
      });

      test('updates lastBuilt timestamp', () async {
        final recordings = _createSampleRecordings();

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => recordings,
        );
        when(mockSearchService.buildIndex(any)).thenAnswer((_) async {});

        expect(manager.lastBuilt, isNull);

        await manager.rebuildIndex();

        expect(manager.lastBuilt, isNotNull);
        expect(
          manager.lastBuilt!.difference(DateTime.now()).inSeconds,
          lessThan(1),
        );
      });

      test('handles concurrent rebuild requests', () async {
        final recordings = _createSampleRecordings();

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => recordings,
        );
        when(mockSearchService.buildIndex(any)).thenAnswer(
          (_) async => await Future.delayed(const Duration(milliseconds: 100)),
        );

        // Start two rebuilds concurrently
        final future1 = manager.rebuildIndex();
        final future2 = manager.rebuildIndex();

        await Future.wait([future1, future2]);

        // Should only call buildIndex once (second call waits for first)
        verify(mockSearchService.buildIndex(recordings)).called(1);
      });

      test('clears isBuilding flag on error', () async {
        when(mockStorageService.getRecordings()).thenThrow(
          Exception('Storage error'),
        );

        expect(manager.isBuilding, false);

        try {
          await manager.rebuildIndex();
          fail('Should have thrown exception');
        } catch (e) {
          expect(e.toString(), contains('Storage error'));
        }

        // Should not be stuck in building state
        expect(manager.isBuilding, false);
      });

      test('propagates errors from storage service', () async {
        when(mockStorageService.getRecordings()).thenThrow(
          Exception('Storage error'),
        );

        expect(
          () => manager.rebuildIndex(),
          throwsException,
        );
      });

      test('propagates errors from search service', () async {
        final recordings = _createSampleRecordings();

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => recordings,
        );
        when(mockSearchService.buildIndex(any)).thenThrow(
          Exception('Index build error'),
        );

        expect(
          () => manager.rebuildIndex(),
          throwsException,
        );
      });
    });

    group('invalidate', () {
      test('clears search service index', () {
        when(mockSearchService.clear()).thenReturn(null);

        manager.invalidate();

        verify(mockSearchService.clear()).called(1);
      });

      test('resets lastBuilt timestamp', () async {
        final recordings = _createSampleRecordings();

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => recordings,
        );
        when(mockSearchService.buildIndex(any)).thenAnswer((_) async {});

        await manager.rebuildIndex();
        expect(manager.lastBuilt, isNotNull);

        manager.invalidate();
        expect(manager.lastBuilt, isNull);
      });
    });

    group('getStats', () {
      test('returns correct stats when index not built', () {
        when(mockSearchService.needsRebuild).thenReturn(true);
        when(mockSearchService.indexSize).thenReturn(0);

        final stats = manager.getStats();

        expect(stats['isBuilt'], false);
        expect(stats['isBuilding'], false);
        expect(stats['indexSize'], 0);
        expect(stats['lastBuilt'], isNull);
      });

      test('returns correct stats when index is built', () async {
        final recordings = _createSampleRecordings();

        when(mockSearchService.needsRebuild).thenReturn(false);
        when(mockSearchService.indexSize).thenReturn(recordings.length);
        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => recordings,
        );
        when(mockSearchService.buildIndex(any)).thenAnswer((_) async {});

        await manager.rebuildIndex();

        final stats = manager.getStats();

        expect(stats['isBuilt'], true);
        expect(stats['isBuilding'], false);
        expect(stats['indexSize'], recordings.length);
        expect(stats['lastBuilt'], isNotNull);
      });

      test('returns correct stats during build', () async {
        final recordings = _createSampleRecordings();

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => recordings,
        );
        when(mockSearchService.buildIndex(any)).thenAnswer(
          (_) async => await Future.delayed(const Duration(milliseconds: 100)),
        );
        when(mockSearchService.needsRebuild).thenReturn(true);
        when(mockSearchService.indexSize).thenReturn(0);

        // Start build in background
        final buildFuture = manager.rebuildIndex();

        // Check stats while building
        await Future.delayed(const Duration(milliseconds: 10));
        final stats = manager.getStats();
        expect(stats['isBuilding'], true);

        await buildFuture;
      });
    });

    group('needsRebuild', () {
      test('returns true when search service needs rebuild', () {
        when(mockSearchService.needsRebuild).thenReturn(true);
        expect(manager.needsRebuild, true);
      });

      test('returns false when search service does not need rebuild', () {
        when(mockSearchService.needsRebuild).thenReturn(false);
        expect(manager.needsRebuild, false);
      });
    });

    group('isBuilding', () {
      test('returns false initially', () {
        expect(manager.isBuilding, false);
      });

      test('returns true during build', () async {
        final recordings = _createSampleRecordings();

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => recordings,
        );
        when(mockSearchService.buildIndex(any)).thenAnswer(
          (_) async => await Future.delayed(const Duration(milliseconds: 100)),
        );

        final buildFuture = manager.rebuildIndex();

        // Check immediately after starting
        await Future.delayed(const Duration(milliseconds: 10));
        expect(manager.isBuilding, true);

        await buildFuture;
        expect(manager.isBuilding, false);
      });

      test('returns false after build completes', () async {
        final recordings = _createSampleRecordings();

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => recordings,
        );
        when(mockSearchService.buildIndex(any)).thenAnswer((_) async {});

        await manager.rebuildIndex();

        expect(manager.isBuilding, false);
      });
    });

    group('lastBuilt', () {
      test('returns null initially', () {
        expect(manager.lastBuilt, isNull);
      });

      test('returns timestamp after build', () async {
        final recordings = _createSampleRecordings();

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => recordings,
        );
        when(mockSearchService.buildIndex(any)).thenAnswer((_) async {});

        await manager.rebuildIndex();

        expect(manager.lastBuilt, isNotNull);
      });

      test('returns null after invalidate', () async {
        final recordings = _createSampleRecordings();

        when(mockStorageService.getRecordings()).thenAnswer(
          (_) async => recordings,
        );
        when(mockSearchService.buildIndex(any)).thenAnswer((_) async {});

        await manager.rebuildIndex();
        expect(manager.lastBuilt, isNotNull);

        manager.invalidate();
        expect(manager.lastBuilt, isNull);
      });
    });
  });
}

/// Helper function to create sample recordings for testing
List<Recording> _createSampleRecordings() {
  final now = DateTime.now();

  return [
    Recording(
      id: 'sample-1',
      title: 'Project Alpha Planning',
      filePath: '/test/sample-1.opus',
      timestamp: now.subtract(const Duration(days: 1)),
      duration: const Duration(minutes: 15),
      tags: ['work', 'project-alpha'],
      transcript: 'Discussed project timeline and milestones',
      fileSizeKB: 500.0,
    ),
    Recording(
      id: 'sample-2',
      title: 'Weekly Team Sync',
      filePath: '/test/sample-2.opus',
      timestamp: now.subtract(const Duration(days: 2)),
      duration: const Duration(minutes: 30),
      tags: ['work', 'meeting'],
      transcript: 'Sprint review and backlog grooming',
      fileSizeKB: 1000.0,
    ),
  ];
}
