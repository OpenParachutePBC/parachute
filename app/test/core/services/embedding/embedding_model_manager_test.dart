import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/models/embedding_models.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/embedding/embedding_model_manager.dart';

/// Mock implementation of EmbeddingService for testing
class MockEmbeddingService implements EmbeddingService {
  bool _isReady = false;
  bool _needsDownload = true;
  bool _shouldFailDownload = false;
  bool _shouldFailEmbed = false;

  // Track method calls for verification
  int isReadyCallCount = 0;
  int needsDownloadCallCount = 0;
  int embedCallCount = 0;
  int embedBatchCallCount = 0;

  @override
  int get dimensions => 256;

  void setReady(bool ready) {
    _isReady = ready;
    _needsDownload = !ready;
  }

  void setNeedsDownload(bool needs) {
    _needsDownload = needs;
  }

  void setShouldFailDownload(bool fail) {
    _shouldFailDownload = fail;
  }

  void setShouldFailEmbed(bool fail) {
    _shouldFailEmbed = fail;
  }

  @override
  Future<bool> isReady() async {
    isReadyCallCount++;
    return _isReady;
  }

  @override
  Future<bool> needsDownload() async {
    needsDownloadCallCount++;
    return _needsDownload;
  }

  @override
  Stream<double> downloadModel() async* {
    if (_shouldFailDownload) {
      // Yield first to ensure stream is established before throwing
      yield 0.0;
      throw Exception('Download failed');
    }

    // Simulate download progress
    for (var i = 0; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 10));
      yield i / 10.0;
    }

    // Mark as ready after download
    _isReady = true;
    _needsDownload = false;
  }

  @override
  Future<List<double>> embed(String text) async {
    embedCallCount++;

    if (_shouldFailEmbed) {
      throw Exception('Embedding failed');
    }

    if (!_isReady) {
      throw Exception('Model not ready');
    }

    if (text.isEmpty) {
      throw ArgumentError('Text cannot be empty');
    }

    // Return a mock embedding
    return List.generate(dimensions, (i) => i.toDouble() / dimensions);
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    embedBatchCallCount++;

    if (_shouldFailEmbed) {
      throw Exception('Embedding failed');
    }

    if (!_isReady) {
      throw Exception('Model not ready');
    }

    // Return mock embeddings for each text
    return texts.map((text) {
      return List.generate(dimensions, (i) => i.toDouble() / dimensions);
    }).toList();
  }

  @override
  Future<void> dispose() async {
    // No-op for mock
  }
}

void main() {
  group('EmbeddingModelManager', () {
    late MockEmbeddingService mockService;
    late EmbeddingModelManager manager;

    setUp(() {
      mockService = MockEmbeddingService();
      manager = EmbeddingModelManager(mockService);
    });

    tearDown(() async {
      await manager.dispose();
    });

    group('initialization', () {
      test('starts with notDownloaded status', () {
        expect(manager.status, EmbeddingModelStatus.notDownloaded);
        expect(manager.downloadProgress, 0.0);
        expect(manager.error, null);
      });

      test('exposes embedding service dimensions', () {
        expect(manager.dimensions, 256);
      });
    });

    group('ensureModelReady', () {
      test('sets status to ready if already ready', () async {
        mockService.setReady(true);

        await manager.ensureModelReady();

        expect(manager.status, EmbeddingModelStatus.ready);
        expect(mockService.isReadyCallCount, 1);
        expect(mockService.needsDownloadCallCount, 0);
      });

      test('downloads model if needed', () async {
        mockService.setReady(false);
        mockService.setNeedsDownload(true);

        await manager.ensureModelReady();

        expect(manager.status, EmbeddingModelStatus.ready);
        expect(manager.downloadProgress, 1.0);
      });

      test('sets status to ready if downloaded but not loaded', () async {
        mockService.setReady(false);
        mockService.setNeedsDownload(false);

        await manager.ensureModelReady();

        expect(manager.status, EmbeddingModelStatus.ready);
      });

      test('handles download errors', () async {
        mockService.setReady(false);
        mockService.setNeedsDownload(true);
        mockService.setShouldFailDownload(true);

        await manager.ensureModelReady();

        expect(manager.status, EmbeddingModelStatus.error);
        expect(manager.error, isNotNull);
        expect(manager.error, contains('Download failed'));
      });

      test('is safe to call multiple times', () async {
        mockService.setReady(true);

        await manager.ensureModelReady();
        await manager.ensureModelReady();
        await manager.ensureModelReady();

        expect(manager.status, EmbeddingModelStatus.ready);
        // Should only check once and return early
        expect(mockService.isReadyCallCount, 3);
      });
    });

    group('downloadModel', () {
      test('streams progress updates', () async {
        final progressValues = <double>[];

        await for (final progress in manager.downloadModel()) {
          progressValues.add(progress);
        }

        expect(progressValues.length, greaterThan(5));
        expect(progressValues.first, 0.0);
        expect(progressValues.last, 1.0);
        expect(manager.status, EmbeddingModelStatus.ready);
      });

      test('sets downloading status during download', () async {
        expect(manager.status, EmbeddingModelStatus.notDownloaded);

        final stream = manager.downloadModel();
        await stream.first; // Get first progress update

        expect(manager.status, EmbeddingModelStatus.downloading);
      });

      test('handles download errors', () async {
        mockService.setShouldFailDownload(true);

        // Consume the stream and expect exception
        try {
          await for (final _ in manager.downloadModel()) {
            // Consume stream
          }
          fail('Expected exception to be thrown');
        } catch (e) {
          expect(e.toString(), contains('Download failed'));
        }

        expect(manager.status, EmbeddingModelStatus.error);
        expect(manager.error, isNotNull);
      });
    });

    group('isReady', () {
      test('delegates to embedding service', () async {
        mockService.setReady(false);
        expect(await manager.isReady(), false);

        mockService.setReady(true);
        expect(await manager.isReady(), true);

        expect(mockService.isReadyCallCount, 2);
      });
    });

    group('platform detection', () {
      test('isMobile returns correct value', () {
        // This test will depend on the platform the tests are running on
        // We can't easily mock Platform.isAndroid/isIOS in pure Dart tests
        // So we just verify the method exists and returns a boolean
        expect(EmbeddingModelManager.isMobile, isA<bool>());
      });

      test('isDesktop returns correct value', () {
        expect(EmbeddingModelManager.isDesktop, isA<bool>());
      });
    });

    group('service access', () {
      test('provides access to underlying service', () {
        expect(manager.service, mockService);
      });
    });
  });
}
