import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/recorder/services/vad/smart_chunker.dart';

void main() {
  group('SmartChunker', () {
    group('Configuration', () {
      test('uses default values when not specified', () {
        final chunker = SmartChunker(
          config: SmartChunkerConfig(onChunkReady: (_) {}),
        );

        expect(chunker.config.sampleRate, 16000);
        expect(chunker.config.silenceThreshold, Duration(seconds: 1));
        expect(chunker.config.minChunkDuration, Duration(milliseconds: 500));
        expect(chunker.config.maxChunkDuration, Duration(seconds: 30));
        expect(chunker.config.vadEnergyThreshold, 100.0);
      });

      test('respects custom configuration', () {
        final chunker = SmartChunker(
          config: SmartChunkerConfig(
            sampleRate: 48000,
            silenceThreshold: Duration(seconds: 2),
            minChunkDuration: Duration(seconds: 1),
            maxChunkDuration: Duration(seconds: 60),
            vadEnergyThreshold: 200.0,
            onChunkReady: (_) {},
          ),
        );

        expect(chunker.config.sampleRate, 48000);
        expect(chunker.config.silenceThreshold, Duration(seconds: 2));
        expect(chunker.config.minChunkDuration, Duration(seconds: 1));
        expect(chunker.config.maxChunkDuration, Duration(seconds: 60));
        expect(chunker.config.vadEnergyThreshold, 200.0);
      });
    });

    group('Buffer Management', () {
      test('accumulates samples in buffer', () {
        final chunker = SmartChunker(
          config: SmartChunkerConfig(onChunkReady: (_) {}),
        );

        // Send 160 samples (10ms at 16kHz)
        chunker.processSamples(List.filled(160, 1000));

        final stats = chunker.stats;
        expect(stats.bufferSamples, 160);
      });

      test('calculates buffer duration correctly', () {
        final chunker = SmartChunker(
          config: SmartChunkerConfig(onChunkReady: (_) {}),
        );

        // Send 16000 samples (1 second at 16kHz)
        chunker.processSamples(List.filled(16000, 1000));

        final stats = chunker.stats;
        expect(stats.bufferDuration.inSeconds, 1);
      });

      test('ignores empty sample arrays', () {
        final chunker = SmartChunker(
          config: SmartChunkerConfig(onChunkReady: (_) {}),
        );

        chunker.processSamples([]);

        final stats = chunker.stats;
        expect(stats.bufferSamples, 0);
      });
    });

    group('Automatic Chunking', () {
      test('chunks after 1 second of silence with sufficient speech', () async {
        var chunkCount = 0;

        final chunker = SmartChunker(
          config: SmartChunkerConfig(onChunkReady: (_) => chunkCount++),
        );

        // Send 1 second of speech (100 frames * 160 samples)
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(
            List.filled(160, 1000),
          ); // High energy = speech
        }

        expect(chunkCount, 0); // No chunk yet

        // Send 1 second of silence (100 frames * 160 samples)
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 10)); // Low energy = silence
        }

        // Wait for async callback
        await Future.delayed(Duration(milliseconds: 10));

        expect(chunkCount, 1); // Should have triggered chunk
      });

      test('does not chunk with insufficient speech duration', () async {
        var chunkCount = 0;

        final chunker = SmartChunker(
          config: SmartChunkerConfig(onChunkReady: (_) => chunkCount++),
        );

        // Send only 500ms of speech (not enough)
        for (var i = 0; i < 50; i++) {
          chunker.processSamples(List.filled(160, 1000));
        }

        // Send 1 second of silence
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 10));
        }

        await Future.delayed(Duration(milliseconds: 10));

        expect(chunkCount, 0); // Should NOT chunk (insufficient speech)
      });

      test('chunks at max duration even without silence', () async {
        var chunkCount = 0;

        final chunker = SmartChunker(
          config: SmartChunkerConfig(
            maxChunkDuration: Duration(seconds: 2),
            onChunkReady: (_) => chunkCount++,
          ),
        );

        // Send 2 seconds of continuous speech
        for (var i = 0; i < 200; i++) {
          chunker.processSamples(List.filled(160, 1000));
        }

        await Future.delayed(Duration(milliseconds: 10));

        expect(chunkCount, 1); // Should chunk at max duration
      });

      test('respects minimum chunk duration', () async {
        var chunkCount = 0;

        final chunker = SmartChunker(
          config: SmartChunkerConfig(
            minChunkDuration: Duration(seconds: 3),
            onChunkReady: (_) => chunkCount++,
          ),
        );

        // Send 1 second of speech (100 frames)
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 1000));
        }

        // Send 1 second of silence (100 frames) - triggers shouldChunk in VAD
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 10));
        }

        await Future.delayed(Duration(milliseconds: 10));

        // Should NOT chunk because buffer duration (2s) < minChunkDuration (3s)
        // Even though VAD detected 1s silence and we have ≥1s speech
        expect(chunkCount, 0);
      });
    });

    group('Chunk Content', () {
      test('chunk contains all accumulated samples', () async {
        List<int>? receivedChunk;

        final chunker = SmartChunker(
          config: SmartChunkerConfig(
            onChunkReady: (chunk) => receivedChunk = chunk,
          ),
        );

        // Send 1 second of speech
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 1000));
        }

        // Send 1 second of silence to trigger chunk
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 10));
        }

        await Future.delayed(Duration(milliseconds: 10));

        expect(receivedChunk, isNotNull);
        // Should contain speech + silence samples
        expect(receivedChunk!.length, 16000 + 16000); // 2 seconds total
      });

      test('multiple chunks are independent', () async {
        final chunks = <List<int>>[];

        final chunker = SmartChunker(
          config: SmartChunkerConfig(
            onChunkReady: (chunk) => chunks.add(chunk),
          ),
        );

        // First chunk
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 1000));
        }
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 10));
        }

        await Future.delayed(Duration(milliseconds: 10));

        // Second chunk
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 2000));
        }
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 10));
        }

        await Future.delayed(Duration(milliseconds: 10));

        expect(chunks.length, 2);
        // Chunks should be different (different speech energy)
        expect(chunks[0].first, 1000);
        expect(chunks[1].first, 2000);
      });
    });

    group('Flush Behavior', () {
      test('flush sends chunk with sufficient speech', () async {
        var chunkCount = 0;

        final chunker = SmartChunker(
          config: SmartChunkerConfig(onChunkReady: (_) => chunkCount++),
        );

        // Send 1 second of speech
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 1000));
        }

        // Flush manually
        chunker.flush();

        await Future.delayed(Duration(milliseconds: 10));

        expect(chunkCount, 1);
      });

      test('flush discards chunk with insufficient speech', () async {
        var chunkCount = 0;

        final chunker = SmartChunker(
          config: SmartChunkerConfig(onChunkReady: (_) => chunkCount++),
        );

        // Send only 500ms of speech (not enough)
        for (var i = 0; i < 50; i++) {
          chunker.processSamples(List.filled(160, 1000));
        }

        // Flush manually
        chunker.flush();

        await Future.delayed(Duration(milliseconds: 10));

        expect(chunkCount, 0); // Should discard
      });

      test('flush on empty buffer does nothing', () {
        final chunker = SmartChunker(
          config: SmartChunkerConfig(
            onChunkReady: (_) => fail('Should not call callback'),
          ),
        );

        // Flush with no data
        chunker.flush();

        // Test passes if callback not called
      });
    });

    group('Statistics', () {
      test('tracks total speech duration across chunks', () async {
        final chunker = SmartChunker(
          config: SmartChunkerConfig(onChunkReady: (_) {}),
        );

        // First chunk: 1s speech
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 1000));
        }
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 10));
        }

        await Future.delayed(Duration(milliseconds: 10));

        // Second chunk: 1s speech
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 1000));
        }
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 10));
        }

        await Future.delayed(Duration(milliseconds: 10));

        final stats = chunker.stats;
        expect(stats.totalSpeech.inSeconds, 2); // Should accumulate
      });

      test('stats includes VAD statistics', () {
        final chunker = SmartChunker(
          config: SmartChunkerConfig(onChunkReady: (_) {}),
        );

        // Send some speech
        for (var i = 0; i < 50; i++) {
          chunker.processSamples(List.filled(160, 1000));
        }

        final stats = chunker.stats;
        expect(stats.vadStats.isSpeaking, true);
        expect(stats.vadStats.speechDuration.inMilliseconds, greaterThan(0));
      });
    });

    group('Reset Functionality', () {
      test('reset clears all state', () {
        final chunker = SmartChunker(
          config: SmartChunkerConfig(onChunkReady: (_) {}),
        );

        // Accumulate some data
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 1000));
        }

        // Reset
        chunker.reset();

        final stats = chunker.stats;
        expect(stats.bufferSamples, 0);
        expect(stats.totalSpeech.inSeconds, 0);
        expect(stats.vadStats.speechDuration.inSeconds, 0);
      });
    });

    group('Real-world Scenarios', () {
      test('handles speech with short pauses', () async {
        var chunkCount = 0;

        final chunker = SmartChunker(
          config: SmartChunkerConfig(onChunkReady: (_) => chunkCount++),
        );

        // Speech for 1s
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 1000));
        }

        // Short pause (300ms - not enough to trigger)
        for (var i = 0; i < 30; i++) {
          chunker.processSamples(List.filled(160, 10));
        }

        // More speech
        for (var i = 0; i < 50; i++) {
          chunker.processSamples(List.filled(160, 1000));
        }

        expect(chunkCount, 0); // No chunk yet

        // Long pause (1s - should trigger)
        for (var i = 0; i < 100; i++) {
          chunker.processSamples(List.filled(160, 10));
        }

        await Future.delayed(Duration(milliseconds: 10));

        expect(chunkCount, 1);
      });

      test('handles alternating speech and silence', () async {
        var chunkCount = 0;

        final chunker = SmartChunker(
          config: SmartChunkerConfig(onChunkReady: (_) => chunkCount++),
        );

        for (var cycle = 0; cycle < 3; cycle++) {
          // Speech (1s)
          for (var i = 0; i < 100; i++) {
            chunker.processSamples(List.filled(160, 1000));
          }

          // Silence (1s)
          for (var i = 0; i < 100; i++) {
            chunker.processSamples(List.filled(160, 10));
          }

          await Future.delayed(Duration(milliseconds: 10));
        }

        expect(chunkCount, 3); // Should create 3 chunks
      });
    });
  });
}
