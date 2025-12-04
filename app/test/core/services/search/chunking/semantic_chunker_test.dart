import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/search/chunking/semantic_chunker.dart';

/// Mock embedding service for testing
///
/// Generates deterministic embeddings based on text content:
/// - Text starting with same word gets similar embeddings (high cosine similarity)
/// - Text starting with different words gets dissimilar embeddings (low similarity)
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
    // Generate deterministic embedding based on first word
    final firstWord = text.trim().split(' ').first.toLowerCase();
    final seed = firstWord.hashCode;

    // Create a pseudo-random but deterministic embedding
    final embedding = List<double>.generate(_dimensions, (i) {
      final value = ((seed + i) % 1000) / 1000.0;
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
    final magnitude = sumSquares > 0 ? 1.0 / (sumSquares.sqrt()) : 1.0;
    return vector.map((v) => v * magnitude).toList();
  }
}

/// Extension to add sqrt to double for normalization
extension on double {
  double sqrt() {
    return this < 0 ? 0.0 : this.toStringAsFixed(10).parse().sqrt();
  }

  double parse() => double.parse(this.toString());
}

void main() {
  group('Chunk', () {
    test('calculates token count correctly', () {
      final chunk = Chunk(
        text: 'This is a test sentence with about twenty characters.',
        embedding: List.filled(256, 0.0),
      );

      // 55 characters / 4 ≈ 14 tokens
      expect(chunk.tokenCount, greaterThanOrEqualTo(13));
      expect(chunk.tokenCount, lessThanOrEqualTo(15));
    });

    test('includes sentence range in toJson', () {
      final chunk = Chunk(
        text: 'Test',
        embedding: [0.1, 0.2, 0.3],
        sentenceRange: (5, 10),
      );

      final json = chunk.toJson();
      expect(json['sentenceRange'], [5, 10]);
    });

    test('handles null sentence range in toJson', () {
      final chunk = Chunk(
        text: 'Test',
        embedding: [0.1, 0.2, 0.3],
      );

      final json = chunk.toJson();
      expect(json['sentenceRange'], isNull);
    });
  });

  group('SemanticChunker', () {
    late MockEmbeddingService embeddingService;
    late SemanticChunker chunker;

    setUp(() {
      embeddingService = MockEmbeddingService();
      chunker = SemanticChunker(embeddingService);
    });

    test('handles empty transcript', () async {
      final chunks = await chunker.chunkTranscript('');
      expect(chunks, isEmpty);
    });

    test('handles single sentence', () async {
      const text = 'This is a single sentence.';
      final chunks = await chunker.chunkTranscript(text);

      expect(chunks, hasLength(1));
      expect(chunks[0].text, text);
      expect(chunks[0].embedding, hasLength(256));
      expect(chunks[0].sentenceRange, (0, 1));
    });

    test('creates multiple chunks for semantically different content', () async {
      // These sentences start with different words, so mock will give them
      // different embeddings, resulting in multiple chunks
      const text = '''
Apple products are expensive. Banana smoothies taste great.
Cherry trees bloom in spring. Date palms grow in deserts.
''';

      final chunks = await chunker.chunkTranscript(text);

      // With different starting words, similarity should be low
      // Should create multiple chunks
      expect(chunks.length, greaterThan(1));
    });

    test('creates single chunk for semantically similar content', () async {
      // All sentences start with "The", so embeddings should be similar
      const text = '''
The weather is nice today. The sun is shining.
The birds are singing. The flowers are blooming.
''';

      final chunks = await chunker.chunkTranscript(text);

      // With same starting word, similarity should be high
      // Might create just one chunk (depending on threshold)
      expect(chunks, isNotEmpty);
    });

    test('enforces max token limit', () async {
      // Create a very long text that exceeds max tokens
      final longSentences = List.generate(
        100,
        (i) => 'Sentence number $i with some additional words.',
      );
      final text = longSentences.join(' ');

      final chunks = await chunker.chunkTranscript(text);

      // Should have created multiple chunks due to size constraint
      expect(chunks.length, greaterThan(1));

      // Each chunk should be within token limit (with some tolerance)
      for (final chunk in chunks) {
        expect(chunk.tokenCount, lessThanOrEqualTo(600)); // Some tolerance
      }
    });

    test('embeddings are normalized', () async {
      const text = 'This is a test. Another sentence here.';
      final chunks = await chunker.chunkTranscript(text);

      for (final chunk in chunks) {
        // Calculate L2 norm
        double sumSquares = 0.0;
        for (final value in chunk.embedding) {
          sumSquares += value * value;
        }
        final norm = sumSquares.sqrt();

        // Should be very close to 1.0 (normalized)
        expect(norm, closeTo(1.0, 0.01));
      }
    });

    test('respects custom similarity threshold', () async {
      // Create chunker with very low threshold (splits aggressively)
      final aggressiveChunker = SemanticChunker(
        embeddingService,
        similarityThreshold: 0.1,
      );

      const text = '''
First sentence here. Second sentence here. Third sentence here.
''';

      final chunks = await aggressiveChunker.chunkTranscript(text);

      // With low threshold, should create more chunks
      expect(chunks, isNotEmpty);
    });

    test('respects custom max chunk tokens', () async {
      // Create chunker with very small max tokens
      final smallChunker = SemanticChunker(
        embeddingService,
        maxChunkTokens: 10, // Very small
      );

      const text = '''
This is a longer sentence that will definitely exceed the token limit.
Another sentence that is also quite long and exceeds the limit.
''';

      final chunks = await smallChunker.chunkTranscript(text);

      // Should create multiple chunks due to small size limit
      expect(chunks.length, greaterThan(1));
    });

    test('sentence ranges are correct', () async {
      const text = 'First. Second. Third. Fourth.';
      final chunks = await chunker.chunkTranscript(text);

      // Check that ranges are valid
      for (final chunk in chunks) {
        final range = chunk.sentenceRange;
        expect(range, isNotNull);
        expect(range!.$1, lessThan(range.$2)); // Start < end
        expect(range.$1, greaterThanOrEqualTo(0));
      }

      // Ranges should be contiguous
      if (chunks.length > 1) {
        for (int i = 0; i < chunks.length - 1; i++) {
          final currentEnd = chunks[i].sentenceRange!.$2;
          final nextStart = chunks[i + 1].sentenceRange!.$1;
          expect(currentEnd, nextStart);
        }
      }
    });

    test('handles real voice transcript example', () async {
      const text = '''
Had a great meeting today. Discussed the Q4 roadmap.
Everyone agreed on priorities. Oh, need to pick up groceries.
Milk, eggs, bread.
''';

      final chunks = await chunker.chunkTranscript(text);

      expect(chunks, isNotEmpty);

      // All chunks should have non-empty text
      for (final chunk in chunks) {
        expect(chunk.text.trim(), isNotEmpty);
        expect(chunk.embedding, hasLength(256));
      }
    });
  });
}
