import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/recorder/services/audio_processing/simple_noise_filter.dart';
import 'dart:math';

void main() {
  group('SimpleNoiseFilter', () {
    test('should pass through DC signal (0 Hz) - gets filtered out', () {
      final filter = SimpleNoiseFilter(cutoffFreq: 80.0, sampleRate: 16000);

      // DC signal (constant value) should be filtered out by high-pass
      final input = List.filled(100, 1000);
      final output = filter.process(input);

      expect(output.length, input.length);

      // DC should be attenuated (moving toward zero over time)
      final avgOutput = output.reduce((a, b) => a + b) / output.length;
      expect(avgOutput.abs(), lessThan(500)); // Lower than input (1000)
    });

    test('should pass high-frequency signal (voice range ~200Hz+)', () {
      final filter = SimpleNoiseFilter(cutoffFreq: 80.0, sampleRate: 16000);

      // Generate 300Hz sine wave (typical voice fundamental)
      final frequency = 300.0;
      final sampleRate = 16000;
      final amplitude = 10000;

      final input = List.generate(
        160, // 10ms at 16kHz
        (i) => (amplitude * sin(2 * pi * frequency * i / sampleRate)).round(),
      );

      final output = filter.process(input);

      expect(output.length, input.length);

      // High frequency should pass through with minimal attenuation
      final inputRMS = _calculateRMS(input);
      final outputRMS = _calculateRMS(output);

      // Output should be close to input (>80% amplitude retained)
      expect(outputRMS, greaterThan(inputRMS * 0.8));
    });

    test('should filter low-frequency noise (60Hz hum)', () {
      final filter = SimpleNoiseFilter(cutoffFreq: 80.0, sampleRate: 16000);

      // Generate 60Hz sine wave (AC power hum)
      final frequency = 60.0;
      final sampleRate = 16000;
      final amplitude = 5000;

      final input = List.generate(
        160,
        (i) => (amplitude * sin(2 * pi * frequency * i / sampleRate)).round(),
      );

      final output = filter.process(input);

      // 60Hz should be attenuated
      final inputRMS = _calculateRMS(input);
      final outputRMS = _calculateRMS(output);

      // Output should be lower than input (<60% retained)
      // Note: High-pass filters have gradual rolloff
      expect(outputRMS, lessThan(inputRMS * 0.6));
    });

    test('should handle empty input', () {
      final filter = SimpleNoiseFilter();
      final output = filter.process([]);
      expect(output, isEmpty);
    });

    test('should clamp output to int16 range', () {
      final filter = SimpleNoiseFilter();

      // Input near max int16 value
      final input = List.filled(10, 32000);
      final output = filter.process(input);

      // All outputs should be valid int16
      for (final sample in output) {
        expect(sample, greaterThanOrEqualTo(-32768));
        expect(sample, lessThanOrEqualTo(32767));
      }
    });

    test('should reset state correctly', () {
      final filter = SimpleNoiseFilter();

      // Process some samples
      final input1 = List.filled(100, 5000);
      filter.process(input1);

      // Reset
      filter.reset();

      // Process same input again
      final input2 = List.filled(100, 5000);
      final output1 = filter.process(input1);
      filter.reset();
      final output2 = filter.process(input2);

      // Outputs should be identical (state was reset)
      expect(output1.length, output2.length);
      // First few samples should match (within rounding)
      for (var i = 0; i < 10; i++) {
        expect((output1[i] - output2[i]).abs(), lessThan(2));
      }
    });

    test('should use custom cutoff frequency', () {
      // Lower cutoff = more aggressive filtering
      final filterLow = SimpleNoiseFilter(cutoffFreq: 50.0, sampleRate: 16000);
      final filterHigh = SimpleNoiseFilter(
        cutoffFreq: 150.0,
        sampleRate: 16000,
      );

      // Test 100Hz signal (between the two cutoffs)
      final frequency = 100.0;
      final input = List.generate(
        160,
        (i) => (5000 * sin(2 * pi * frequency * i / 16000)).round(),
      );

      final outputLow = filterLow.process(List.from(input));
      final outputHigh = filterHigh.process(List.from(input));

      final rmsLow = _calculateRMS(outputLow);
      final rmsHigh = _calculateRMS(outputHigh);

      // 150Hz cutoff should attenuate 100Hz more than 50Hz cutoff
      expect(rmsHigh, lessThan(rmsLow));
    });
  });
}

/// Calculate RMS (Root Mean Square) energy
double _calculateRMS(List<int> samples) {
  if (samples.isEmpty) return 0.0;

  double sumSquares = 0.0;
  for (final sample in samples) {
    sumSquares += sample * sample;
  }

  return sqrt(sumSquares / samples.length);
}
