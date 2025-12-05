import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/services/embedding/embedding_service.dart';

void main() {
  group('EmbeddingDimensionHelper', () {
    group('truncate', () {
      test('truncates 768d to 256d', () {
        // Create a 768-dimensional vector
        final embedding = List.generate(768, (i) => i.toDouble());

        // Truncate to 256 dimensions
        final truncated = EmbeddingDimensionHelper.truncate(
          embedding,
          256,
          renormalize: false,
        );

        expect(truncated.length, 256);
        expect(truncated[0], 0.0);
        expect(truncated[255], 255.0);
      });

      test('truncates 768d to 512d', () {
        final embedding = List.generate(768, (i) => i.toDouble());
        final truncated = EmbeddingDimensionHelper.truncate(
          embedding,
          512,
          renormalize: false,
        );

        expect(truncated.length, 512);
        expect(truncated[0], 0.0);
        expect(truncated[511], 511.0);
      });

      test('throws error if target dimensions too large', () {
        final embedding = List.generate(256, (i) => i.toDouble());

        expect(
          () => EmbeddingDimensionHelper.truncate(embedding, 512),
          throwsArgumentError,
        );
      });

      test('renormalizes by default', () {
        // Create a normalized 768d vector
        final embedding = List.generate(768, (i) => 1.0 / 768);

        // Truncate to 256d with renormalization
        final truncated = EmbeddingDimensionHelper.truncate(embedding, 256);

        // Check that result is normalized
        expect(
          EmbeddingDimensionHelper.isNormalized(truncated),
          true,
          reason: 'Truncated vector should be normalized',
        );
      });

      test('can skip renormalization', () {
        // Create a vector where each element is 1.0
        final embedding = List.generate(768, (i) => 1.0);

        // Truncate without renormalization
        final truncated = EmbeddingDimensionHelper.truncate(
          embedding,
          256,
          renormalize: false,
        );

        // Each element should still be 1.0
        expect(truncated.every((v) => v == 1.0), true);

        // Vector should NOT be normalized (magnitude = sqrt(256))
        expect(
          EmbeddingDimensionHelper.isNormalized(truncated),
          false,
          reason: 'Vector without renormalization should not be normalized',
        );
      });
    });

    group('normalize', () {
      test('normalizes a vector to unit length', () {
        // Create a vector: [3, 4] (magnitude = 5)
        final vector = [3.0, 4.0];

        // Normalize using the private _normalize method via truncate
        final normalized = EmbeddingDimensionHelper.truncate(
          vector,
          2,
          renormalize: true,
        );

        // Should be [0.6, 0.8]
        expect(normalized[0], closeTo(0.6, 0.0001));
        expect(normalized[1], closeTo(0.8, 0.0001));

        // Check magnitude is 1
        expect(
          EmbeddingDimensionHelper.isNormalized(normalized),
          true,
        );
      });

      test('handles zero vector', () {
        final vector = [0.0, 0.0, 0.0];

        final normalized = EmbeddingDimensionHelper.truncate(
          vector,
          3,
          renormalize: true,
        );

        // Should remain zero (no division by zero)
        expect(normalized, [0.0, 0.0, 0.0]);
      });

      test('normalizes high-dimensional vectors correctly', () {
        // Create a 768d vector with all 1s
        final vector = List.generate(768, (i) => 1.0);

        final normalized = EmbeddingDimensionHelper.truncate(
          vector,
          768,
          renormalize: true,
        );

        // Check it's normalized
        expect(
          EmbeddingDimensionHelper.isNormalized(normalized),
          true,
        );

        // Each component should be 1/sqrt(768)
        final expected = 1.0 / math.sqrt(768);
        expect(normalized[0], closeTo(expected, 0.0001));
      });
    });

    group('isNormalized', () {
      test('returns true for unit vectors', () {
        expect(
          EmbeddingDimensionHelper.isNormalized([1.0, 0.0, 0.0]),
          true,
        );
        expect(
          EmbeddingDimensionHelper.isNormalized([0.0, 1.0, 0.0]),
          true,
        );
        expect(
          EmbeddingDimensionHelper.isNormalized([0.0, 0.0, 1.0]),
          true,
        );
      });

      test('returns true for normalized vectors', () {
        // [0.6, 0.8] has magnitude 1
        expect(
          EmbeddingDimensionHelper.isNormalized([0.6, 0.8]),
          true,
        );

        // [0.577, 0.577, 0.577] ≈ [1/sqrt(3), 1/sqrt(3), 1/sqrt(3)]
        final sqrt3 = math.sqrt(3);
        expect(
          EmbeddingDimensionHelper.isNormalized([
            1 / sqrt3,
            1 / sqrt3,
            1 / sqrt3,
          ]),
          true,
        );
      });

      test('returns false for non-normalized vectors', () {
        expect(
          EmbeddingDimensionHelper.isNormalized([1.0, 1.0]),
          false,
          reason: 'Magnitude = ${math.sqrt(2)}',
        );
        expect(
          EmbeddingDimensionHelper.isNormalized([2.0, 0.0]),
          false,
          reason: 'Magnitude = 2',
        );
        expect(
          EmbeddingDimensionHelper.isNormalized([0.5, 0.5]),
          false,
          reason: 'Magnitude < 1',
        );
      });

      test('uses tolerance for floating point errors', () {
        // Create a vector that's almost normalized
        final almostNormalized = [0.6, 0.8000001];

        expect(
          EmbeddingDimensionHelper.isNormalized(
            almostNormalized,
            tolerance: 1e-5,
          ),
          true,
          reason: 'Should accept small floating point errors',
        );

        expect(
          EmbeddingDimensionHelper.isNormalized(
            almostNormalized,
            tolerance: 1e-10,
          ),
          false,
          reason: 'Should reject with stricter tolerance',
        );
      });
    });
  });
}
