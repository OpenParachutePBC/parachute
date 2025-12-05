import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/services/embedding/mobile_embedding_service.dart';

void main() {
  group('MobileEmbeddingService', () {
    late MobileEmbeddingService service;

    setUp(() {
      service = MobileEmbeddingService();
    });

    tearDown(() async {
      await service.dispose();
    });

    group('dimensions', () {
      test('returns 256 (truncated from 768)', () {
        expect(service.dimensions, 256);
      });
    });

    group('needsDownload', () {
      test('returns true when model file does not exist', () async {
        // Since we're in a test environment without the model,
        // needsDownload should return true
        final needsDownload = await service.needsDownload();

        // In test environment, model won't exist
        expect(needsDownload, true);
      });
    });

    group('isReady', () {
      test('returns false when model is not downloaded', () async {
        final isReady = await service.isReady();

        // In test environment, model won't be ready
        expect(isReady, false);
      });
    });

    group('embed', () {
      test('throws exception when text is empty', () async {
        expect(
          () => service.embed(''),
          throwsArgumentError,
        );
      });

      test('throws exception when text is whitespace only', () async {
        expect(
          () => service.embed('   '),
          throwsArgumentError,
        );
      });

      test('throws exception when model is not ready', () async {
        // Try to embed without downloading model
        // flutter_gemma throws StateError when no active embedder is set
        expect(
          () => service.embed('test text'),
          throwsA(anyOf(isA<Exception>(), isA<StateError>())),
        );
      });
    });

    group('embedBatch', () {
      test('returns empty list when given empty list', () async {
        final embeddings = await service.embedBatch([]);
        expect(embeddings, isEmpty);
      });

      test('throws exception when any text is empty', () async {
        expect(
          () => service.embedBatch(['valid', '', 'also valid']),
          throwsArgumentError,
        );
      });

      test('throws exception when any text is whitespace only', () async {
        expect(
          () => service.embedBatch(['valid', '   ', 'also valid']),
          throwsArgumentError,
        );
      });

      test('throws exception when model is not ready', () async {
        // flutter_gemma throws StateError when no active embedder is set
        expect(
          () => service.embedBatch(['test1', 'test2']),
          throwsA(anyOf(isA<Exception>(), isA<StateError>())),
        );
      });
    });

    group('dispose', () {
      test('can be called multiple times safely', () async {
        await service.dispose();
        await service.dispose(); // Should not throw

        expect(true, true); // Test passes if no exception thrown
      });

      test('makes service unusable after disposal', () async {
        await service.dispose();

        // After disposal, operations should fail
        expect(await service.isReady(), false);
        expect(await service.needsDownload(), false);
      });
    });

    group('downloadModel', () {
      test('throws when service is disposed', () async {
        await service.dispose();

        expect(
          () => service.downloadModel().first,
          throwsA(isA<Exception>()),
        );
      });

      // Note: Full download test would require network access and ~300MB download
      // This is better tested manually or in integration tests
    });
  });

  group('MobileEmbeddingService integration (requires model)', () {
    // These tests would need the actual model file to be present
    // They should be run separately as integration tests

    test('MANUAL: embed returns normalized 256d vector', () async {
      // This test requires manual setup:
      // 1. Download the model
      // 2. Place it in the expected location
      // 3. Run this test

      // Uncomment to run manually:
      /*
      final service = MobileEmbeddingService();

      // Wait for model to be ready
      await service.downloadModel().drain();

      final embedding = await service.embed('test text');

      // Check dimensions
      expect(embedding.length, 256);

      // Check normalization (L2 norm should be ~1.0)
      final magnitude = sqrt(embedding.fold<double>(
        0.0,
        (sum, value) => sum + value * value,
      ));
      expect(magnitude, closeTo(1.0, 0.01));

      await service.dispose();
      */
    }, skip: 'Requires manual model download');

    test('MANUAL: embedBatch returns correct number of embeddings', () async {
      // This test requires manual setup (see above)

      // Uncomment to run manually:
      /*
      final service = MobileEmbeddingService();

      await service.downloadModel().drain();

      final texts = ['text 1', 'text 2', 'text 3'];
      final embeddings = await service.embedBatch(texts);

      expect(embeddings.length, 3);
      expect(embeddings[0].length, 256);
      expect(embeddings[1].length, 256);
      expect(embeddings[2].length, 256);

      await service.dispose();
      */
    }, skip: 'Requires manual model download');

    test('MANUAL: similar texts have high cosine similarity', () async {
      // This test requires manual setup (see above)

      // Uncomment to run manually:
      /*
      final service = MobileEmbeddingService();

      await service.downloadModel().drain();

      final embedding1 = await service.embed('The cat sat on the mat');
      final embedding2 = await service.embed('A cat was sitting on a mat');
      final embedding3 = await service.embed('Quantum physics is fascinating');

      // Calculate cosine similarity
      double cosineSimilarity(List<double> a, List<double> b) {
        double dotProduct = 0.0;
        for (int i = 0; i < a.length; i++) {
          dotProduct += a[i] * b[i];
        }
        return dotProduct; // Already normalized, so this is the similarity
      }

      final sim12 = cosineSimilarity(embedding1, embedding2);
      final sim13 = cosineSimilarity(embedding1, embedding3);

      // Similar texts should have higher similarity
      expect(sim12, greaterThan(sim13));
      expect(sim12, greaterThan(0.7)); // Typically >0.8 for very similar texts

      await service.dispose();
      */
    }, skip: 'Requires manual model download');
  });
}
