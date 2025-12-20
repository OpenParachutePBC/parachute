import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/recorder/services/vad/simple_vad.dart';

void main() {
  group('SimpleVAD', () {
    group('Energy Calculation', () {
      test('calculates RMS energy correctly for known samples', () {
        final vad = SimpleVAD();

        // Test case from RichardTate documentation
        // Samples: [100, 200, -150, 300, -250]
        // Expected RMS: sqrt((100^2 + 200^2 + 150^2 + 300^2 + 250^2) / 5)
        // = sqrt((10000 + 40000 + 22500 + 90000 + 62500) / 5)
        // = sqrt(225000 / 5) = sqrt(45000) ≈ 212.13
        final samples = [100, 200, -150, 300, -250];

        final isSpeech = vad.processFrame(samples);

        // With default threshold of 100.0, this should be detected as speech
        expect(isSpeech, true);
      });

      test('detects silence for low-energy samples', () {
        final vad = SimpleVAD(config: VADConfig(energyThreshold: 100.0));

        // Very quiet samples (below threshold)
        final silentSamples = List.filled(160, 10);

        final isSpeech = vad.processFrame(silentSamples);

        expect(isSpeech, false);
      });

      test('detects speech for high-energy samples', () {
        final vad = SimpleVAD(config: VADConfig(energyThreshold: 100.0));

        // Loud samples (above threshold)
        final speechSamples = List.filled(160, 1000);

        final isSpeech = vad.processFrame(speechSamples);

        expect(isSpeech, true);
      });

      test('returns false for empty samples', () {
        final vad = SimpleVAD();

        final isSpeech = vad.processFrame([]);

        expect(isSpeech, false);
      });
    });

    group('State Tracking', () {
      test('tracks consecutive speech frames', () {
        final vad = SimpleVAD(config: VADConfig(energyThreshold: 100.0));

        // Send 5 frames of speech
        for (var i = 0; i < 5; i++) {
          vad.processFrame(List.filled(160, 1000));
        }

        expect(vad.consecutiveSpeech, 5);
        expect(vad.consecutiveSilence, 0);
        expect(vad.isSpeaking, true);
      });

      test('tracks consecutive silence frames', () {
        final vad = SimpleVAD(config: VADConfig(energyThreshold: 100.0));

        // Send 5 frames of silence
        for (var i = 0; i < 5; i++) {
          vad.processFrame(List.filled(160, 10));
        }

        expect(vad.consecutiveSilence, 5);
        expect(vad.consecutiveSpeech, 0);
        expect(vad.isSpeaking, false);
      });

      test('resets consecutive counters on transition', () {
        final vad = SimpleVAD(config: VADConfig(energyThreshold: 100.0));

        // Speech frames
        for (var i = 0; i < 3; i++) {
          vad.processFrame(List.filled(160, 1000));
        }

        expect(vad.consecutiveSpeech, 3);

        // Transition to silence
        vad.processFrame(List.filled(160, 10));

        expect(vad.consecutiveSilence, 1);
        expect(vad.consecutiveSpeech, 0); // Should reset
      });
    });

    group('Duration Tracking', () {
      test('accumulates speech duration correctly', () {
        final vad = SimpleVAD(
          config: VADConfig(energyThreshold: 100.0, frameDurationMs: 10),
        );

        // Send 100 frames of speech (100 * 10ms = 1000ms = 1s)
        for (var i = 0; i < 100; i++) {
          vad.processFrame(List.filled(160, 1000));
        }

        expect(vad.speechDuration.inMilliseconds, 1000);
      });

      test('accumulates silence duration correctly', () {
        final vad = SimpleVAD(
          config: VADConfig(energyThreshold: 100.0, frameDurationMs: 10),
        );

        // Send 100 frames of silence (100 * 10ms = 1000ms = 1s)
        for (var i = 0; i < 100; i++) {
          vad.processFrame(List.filled(160, 10));
        }

        expect(vad.silenceDuration.inMilliseconds, 1000);
      });

      test('resets silence duration when speech detected', () {
        final vad = SimpleVAD(config: VADConfig(energyThreshold: 100.0));

        // Build up silence
        for (var i = 0; i < 50; i++) {
          vad.processFrame(List.filled(160, 10));
        }

        expect(vad.silenceDuration.inMilliseconds, greaterThan(0));

        // Speech should reset silence counter
        vad.processFrame(List.filled(160, 1000));

        expect(vad.silenceDuration.inMilliseconds, 0);
      });
    });

    group('Chunking Logic', () {
      test('shouldChunk returns false before silence threshold', () {
        final vad = SimpleVAD(
          config: VADConfig(
            energyThreshold: 100.0,
            silenceThresholdMs: 1000,
            frameDurationMs: 10,
          ),
        );

        // Send 99 frames of silence (990ms - just under threshold)
        for (var i = 0; i < 99; i++) {
          vad.processFrame(List.filled(160, 10));
        }

        expect(vad.shouldChunk(), false);
      });

      test('shouldChunk returns true after silence threshold', () {
        final vad = SimpleVAD(
          config: VADConfig(
            energyThreshold: 100.0,
            silenceThresholdMs: 1000,
            frameDurationMs: 10,
          ),
        );

        // Send 100 frames of silence (1000ms - at threshold)
        for (var i = 0; i < 100; i++) {
          vad.processFrame(List.filled(160, 10));
        }

        expect(vad.shouldChunk(), true);
      });

      test('shouldChunk returns true well after threshold', () {
        final vad = SimpleVAD(
          config: VADConfig(
            energyThreshold: 100.0,
            silenceThresholdMs: 1000,
            frameDurationMs: 10,
          ),
        );

        // Send 150 frames of silence (1500ms - well over threshold)
        for (var i = 0; i < 150; i++) {
          vad.processFrame(List.filled(160, 10));
        }

        expect(vad.shouldChunk(), true);
        expect(vad.silenceDuration.inMilliseconds, 1500);
      });
    });

    group('Reset Functionality', () {
      test('reset clears all state', () {
        final vad = SimpleVAD(config: VADConfig(energyThreshold: 100.0));

        // Build up state
        for (var i = 0; i < 50; i++) {
          vad.processFrame(List.filled(160, 1000)); // Speech
        }

        expect(vad.speechDuration.inMilliseconds, greaterThan(0));
        expect(vad.consecutiveSpeech, greaterThan(0));

        // Reset
        vad.reset();

        expect(vad.speechDuration.inMilliseconds, 0);
        expect(vad.silenceDuration.inMilliseconds, 0);
        expect(vad.consecutiveSpeech, 0);
        expect(vad.consecutiveSilence, 0);
        expect(vad.isSpeaking, false);
      });
    });

    group('VADStats', () {
      test('stats returns current state', () {
        final vad = SimpleVAD(
          config: VADConfig(energyThreshold: 100.0, frameDurationMs: 10),
        );

        // Process some frames
        for (var i = 0; i < 10; i++) {
          vad.processFrame(List.filled(160, 1000)); // Speech
        }

        final stats = vad.stats;

        expect(stats.speechDuration.inMilliseconds, 100);
        expect(stats.consecutiveSpeech, 10);
        expect(stats.isSpeaking, true);
      });

      test('stats toString is readable', () {
        final stats = VADStats(
          silenceDuration: Duration(milliseconds: 500),
          speechDuration: Duration(milliseconds: 1000),
          consecutiveSilence: 5,
          consecutiveSpeech: 10,
          isSpeaking: true,
        );

        final str = stats.toString();

        expect(str, contains('silence: 500ms'));
        expect(str, contains('speech: 1000ms'));
        expect(str, contains('consecutiveSilence: 5'));
        expect(str, contains('consecutiveSpeech: 10'));
        expect(str, contains('isSpeaking: true'));
      });
    });

    group('Configuration', () {
      test('uses default config when not provided', () {
        final vad = SimpleVAD();

        expect(vad.config.sampleRate, 16000);
        expect(vad.config.frameDurationMs, 10);
        expect(vad.config.energyThreshold, 100.0);
        expect(vad.config.silenceThresholdMs, 1000);
      });

      test('uses custom config when provided', () {
        final vad = SimpleVAD(
          config: VADConfig(
            sampleRate: 48000,
            frameDurationMs: 20,
            energyThreshold: 200.0,
            silenceThresholdMs: 2000,
          ),
        );

        expect(vad.config.sampleRate, 48000);
        expect(vad.config.frameDurationMs, 20);
        expect(vad.config.energyThreshold, 200.0);
        expect(vad.config.silenceThresholdMs, 2000);
      });

      test('calculates samplesPerFrame correctly', () {
        final vad16k = SimpleVAD(
          config: VADConfig(sampleRate: 16000, frameDurationMs: 10),
        );

        // 16000 samples/sec * 10ms = 160 samples
        expect(vad16k.samplesPerFrame, 160);

        final vad48k = SimpleVAD(
          config: VADConfig(sampleRate: 48000, frameDurationMs: 10),
        );

        // 48000 samples/sec * 10ms = 480 samples
        expect(vad48k.samplesPerFrame, 480);
      });
    });

    group('Real-world Scenarios', () {
      test('handles speech with pauses', () {
        final vad = SimpleVAD(
          config: VADConfig(
            energyThreshold: 100.0,
            silenceThresholdMs: 1000,
            frameDurationMs: 10,
          ),
        );

        // Speech for 500ms
        for (var i = 0; i < 50; i++) {
          vad.processFrame(List.filled(160, 1000));
        }

        expect(vad.shouldChunk(), false);

        // Short pause (200ms - not enough to chunk)
        for (var i = 0; i < 20; i++) {
          vad.processFrame(List.filled(160, 10));
        }

        expect(vad.shouldChunk(), false);

        // More speech
        for (var i = 0; i < 50; i++) {
          vad.processFrame(List.filled(160, 1000));
        }

        // Silence counter should have reset
        expect(vad.silenceDuration.inMilliseconds, 0);

        // Long pause (1000ms - should trigger chunk)
        for (var i = 0; i < 100; i++) {
          vad.processFrame(List.filled(160, 10));
        }

        expect(vad.shouldChunk(), true);
      });

      test('handles alternating speech and silence', () {
        final vad = SimpleVAD(config: VADConfig(energyThreshold: 100.0));

        for (var cycle = 0; cycle < 5; cycle++) {
          // Speech
          vad.processFrame(List.filled(160, 1000));
          expect(vad.isSpeaking, true);

          // Silence
          vad.processFrame(List.filled(160, 10));
          expect(vad.isSpeaking, false);
        }
      });
    });
  });
}
