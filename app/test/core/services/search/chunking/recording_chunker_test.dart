import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/search/chunking/recording_chunker.dart';
import 'package:app/features/recorder/models/recording.dart';

/// Mock embedding service for testing
class MockEmbeddingService implements EmbeddingService {
  static const int _dimensions = 256;

  @override
  int get dimensions => _dimensions;

  @override
  Future<bool> isReady() async => true;

  @override
  Future<bool> needsDownload() async => false;

  @override
  Stream<double> downloadModel() async* {
    throw UnimplementedError('Download not supported in mock');
  }

  @override
  Future<List<double>> embed(String text) async {
    // Generate deterministic embedding based on text hash
    final seed = text.hashCode.abs();

    // Create a pseudo-random but deterministic embedding
    final embedding = List<double>.generate(_dimensions, (i) {
      final value = ((seed + i * 17) % 1000) / 1000.0 - 0.5;
      return value;
    });

    // Normalize to unit length
    return _normalize(embedding);
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    return Future.wait(texts.map((text) => embed(text)));
  }

  @override
  Future<void> dispose() async {
    // No-op for mock
  }

  List<double> _normalize(List<double> vector) {
    double sumSquares = 0.0;
    for (final value in vector) {
      sumSquares += value * value;
    }
    final magnitude = sumSquares > 0 ? 1.0 / _sqrt(sumSquares) : 1.0;
    return vector.map((v) => v * magnitude).toList();
  }

  double _sqrt(double value) {
    // Simple Newton's method for square root
    if (value <= 0) return 0.0;
    double x = value;
    for (int i = 0; i < 10; i++) {
      x = (x + value / x) / 2;
    }
    return x;
  }
}

void main() {
  group('RecordingChunker', () {
    late MockEmbeddingService embeddingService;
    late RecordingChunker chunker;

    setUp(() {
      embeddingService = MockEmbeddingService();
      chunker = RecordingChunker(embeddingService);
    });

    test('chunks recording with all fields present', () async {
      final recording = Recording(
        id: 'test-123',
        title: 'Meeting Notes',
        transcript: 'We discussed the project. Everyone agreed. Moving forward.',
        context: 'Weekly team meeting',
        summary: 'Project discussion and agreement',
        filePath: '/path/to/audio.opus',
        timestamp: DateTime.now(),
        duration: const Duration(minutes: 5),
        tags: [],
        fileSizeKB: 1024,
      );

      final chunks = await chunker.chunkRecording(recording);

      // Should have chunks for: transcript (3 sentences), title, context, summary
      // Minimum 4 chunks (could be more if transcript splits)
      expect(chunks.length, greaterThanOrEqualTo(4));

      // Find chunks by field
      final transcriptChunks = chunks.where((c) => c.field == 'transcript').toList();
      final titleChunks = chunks.where((c) => c.field == 'title').toList();
      final contextChunks = chunks.where((c) => c.field == 'context').toList();
      final summaryChunks = chunks.where((c) => c.field == 'summary').toList();

      expect(transcriptChunks, isNotEmpty);
      expect(titleChunks, hasLength(1));
      expect(contextChunks, hasLength(1));
      expect(summaryChunks, hasLength(1));

      // Verify all chunks have correct recording ID
      for (final chunk in chunks) {
        expect(chunk.recordingId, 'test-123');
      }
    });

    test('chunks recording with only transcript and title', () async {
      final recording = Recording(
        id: 'test-456',
        title: 'Quick Note',
        transcript: 'Just a quick thought. Nothing fancy.',
        context: '',
        summary: '',
        filePath: '/path/to/audio.opus',
        timestamp: DateTime.now(),
        duration: const Duration(minutes: 1),
        tags: [],
        fileSizeKB: 256,
      );

      final chunks = await chunker.chunkRecording(recording);

      // Should have chunks for: transcript, title only
      expect(chunks.length, greaterThanOrEqualTo(2));

      final contextChunks = chunks.where((c) => c.field == 'context').toList();
      final summaryChunks = chunks.where((c) => c.field == 'summary').toList();

      expect(contextChunks, isEmpty); // Empty context not chunked
      expect(summaryChunks, isEmpty); // Empty summary not chunked
    });

    test('handles empty transcript', () async {
      final recording = Recording(
        id: 'test-789',
        title: 'Empty Recording',
        transcript: '',
        context: '',
        summary: '',
        filePath: '/path/to/audio.opus',
        timestamp: DateTime.now(),
        duration: const Duration(seconds: 0),
        tags: [],
        fileSizeKB: 10,
      );

      final chunks = await chunker.chunkRecording(recording);

      // Should only have title chunk
      expect(chunks, hasLength(1));
      expect(chunks[0].field, 'title');
    });

    test('transcript chunks have sequential indices', () async {
      final recording = Recording(
        id: 'test-seq',
        title: 'Test',
        transcript: 'First sentence. Second sentence. Third sentence. Fourth sentence.',
        filePath: '/path/to/audio.opus',
        timestamp: DateTime.now(),
        duration: const Duration(minutes: 2),
        tags: [],
        fileSizeKB: 512,
      );

      final chunks = await chunker.chunkRecording(recording);
      final transcriptChunks = chunks.where((c) => c.field == 'transcript').toList();

      // Verify indices are sequential
      for (int i = 0; i < transcriptChunks.length; i++) {
        expect(transcriptChunks[i].chunkIndex, i);
      }
    });

    test('all embeddings are 256 dimensions', () async {
      final recording = Recording(
        id: 'test-dims',
        title: 'Dimension Test',
        transcript: 'Testing embeddings.',
        context: 'Test context',
        summary: 'Test summary',
        filePath: '/path/to/audio.opus',
        timestamp: DateTime.now(),
        duration: const Duration(minutes: 1),
        tags: [],
        fileSizeKB: 256,
      );

      final chunks = await chunker.chunkRecording(recording);

      for (final chunk in chunks) {
        expect(chunk.embedding, hasLength(256));
      }
    });

    test('all embeddings are normalized', () async {
      final recording = Recording(
        id: 'test-norm',
        title: 'Normalization Test',
        transcript: 'Testing vector normalization.',
        filePath: '/path/to/audio.opus',
        timestamp: DateTime.now(),
        duration: const Duration(minutes: 1),
        tags: [],
        fileSizeKB: 256,
      );

      final chunks = await chunker.chunkRecording(recording);

      for (final chunk in chunks) {
        // Calculate L2 norm
        double sumSquares = 0.0;
        for (final value in chunk.embedding) {
          sumSquares += value * value;
        }

        // Newton's method for sqrt
        double norm = sumSquares;
        for (int i = 0; i < 10; i++) {
          norm = (norm + sumSquares / norm) / 2;
        }

        // Should be very close to 1.0 (normalized)
        expect(norm, closeTo(1.0, 0.01));
      }
    });

    test('chunk text is non-empty', () async {
      final recording = Recording(
        id: 'test-text',
        title: 'Text Test',
        transcript: 'First sentence. Second sentence.',
        context: 'Some context',
        filePath: '/path/to/audio.opus',
        timestamp: DateTime.now(),
        duration: const Duration(minutes: 1),
        tags: [],
        fileSizeKB: 256,
      );

      final chunks = await chunker.chunkRecording(recording);

      for (final chunk in chunks) {
        expect(chunk.chunkText.trim(), isNotEmpty);
      }
    });

    test('respects custom similarity threshold', () async {
      final aggressiveChunker = RecordingChunker(
        embeddingService,
        similarityThreshold: 0.1, // Very low - splits more
      );

      final recording = Recording(
        id: 'test-threshold',
        title: 'Threshold Test',
        transcript: 'One sentence. Two sentence. Three sentence. Four sentence.',
        filePath: '/path/to/audio.opus',
        timestamp: DateTime.now(),
        duration: const Duration(minutes: 2),
        tags: [],
        fileSizeKB: 512,
      );

      final chunks = await aggressiveChunker.chunkRecording(recording);
      final transcriptChunks = chunks.where((c) => c.field == 'transcript').toList();

      // With low threshold, should create more chunks
      expect(transcriptChunks, isNotEmpty);
    });

    test('respects custom max chunk tokens', () async {
      final smallChunker = RecordingChunker(
        embeddingService,
        maxChunkTokens: 5, // Very small
      );

      final recording = Recording(
        id: 'test-tokens',
        title: 'Token Test',
        transcript: 'This is a long sentence that exceeds the token limit. Another long sentence here.',
        filePath: '/path/to/audio.opus',
        timestamp: DateTime.now(),
        duration: const Duration(minutes: 2),
        tags: [],
        fileSizeKB: 512,
      );

      final chunks = await smallChunker.chunkRecording(recording);
      final transcriptChunks = chunks.where((c) => c.field == 'transcript').toList();

      // With small token limit, should create multiple chunks
      expect(transcriptChunks.length, greaterThan(1));
    });

    test('batch chunking processes multiple recordings', () async {
      final recordings = [
        Recording(
          id: 'batch-1',
          title: 'First',
          transcript: 'First recording.',
          filePath: '/path/to/audio1.opus',
          timestamp: DateTime.now(),
          duration: const Duration(minutes: 1),
          tags: [],
          fileSizeKB: 256,
        ),
        Recording(
          id: 'batch-2',
          title: 'Second',
          transcript: 'Second recording.',
          filePath: '/path/to/audio2.opus',
          timestamp: DateTime.now(),
          duration: const Duration(minutes: 1),
          tags: [],
          fileSizeKB: 256,
        ),
        Recording(
          id: 'batch-3',
          title: 'Third',
          transcript: 'Third recording.',
          filePath: '/path/to/audio3.opus',
          timestamp: DateTime.now(),
          duration: const Duration(minutes: 1),
          tags: [],
          fileSizeKB: 256,
        ),
      ];

      final chunks = await chunker.chunkRecordings(recordings);

      // Should have chunks from all three recordings
      expect(chunks.length, greaterThanOrEqualTo(6)); // At least 2 per recording

      // Verify all recording IDs are present
      final recordingIds = chunks.map((c) => c.recordingId).toSet();
      expect(recordingIds, contains('batch-1'));
      expect(recordingIds, contains('batch-2'));
      expect(recordingIds, contains('batch-3'));
    });

    test('handles real voice transcript', () async {
      final recording = Recording(
        id: 'real-example',
        title: 'Q4 Planning Meeting',
        transcript: '''
Had a great meeting today. Discussed the Q4 roadmap.
Everyone agreed on priorities. Sarah will lead the mobile effort.
Mike is handling the backend infrastructure. We need to hire two more engineers.
Timeline is aggressive but achievable. Next check-in is Friday.
''',
        context: 'Weekly team planning session',
        summary: 'Q4 roadmap discussion with clear assignments and timeline',
        filePath: '/path/to/audio.opus',
        timestamp: DateTime.now(),
        duration: const Duration(minutes: 15),
        tags: ['meeting', 'planning', 'q4'],
        fileSizeKB: 2048,
      );

      final chunks = await chunker.chunkRecording(recording);

      // Should have chunks for transcript (multiple), title, context, summary
      expect(chunks.length, greaterThanOrEqualTo(4));

      // Verify field distribution
      final fields = chunks.map((c) => c.field).toSet();
      expect(fields, contains('transcript'));
      expect(fields, contains('title'));
      expect(fields, contains('context'));
      expect(fields, contains('summary'));

      // All chunks should have valid data
      for (final chunk in chunks) {
        expect(chunk.recordingId, 'real-example');
        expect(chunk.chunkText.trim(), isNotEmpty);
        expect(chunk.embedding, hasLength(256));
        expect(chunk.chunkIndex, greaterThanOrEqualTo(0));
      }
    });
  });
}
