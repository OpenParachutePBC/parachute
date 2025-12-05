import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/search/chunking/sentence_splitter.dart';

/// A chunk of text with its embedding
class Chunk {
  /// The text content of this chunk
  final String text;

  /// Pre-computed embedding vector (normalized)
  final List<double> embedding;

  /// Which sentences this chunk spans (for highlighting)
  /// Format: (start index, end index) - end is exclusive
  final (int, int)? sentenceRange;

  Chunk({
    required this.text,
    required this.embedding,
    this.sentenceRange,
  });

  /// Approximate token count (rough estimate: 1 token ≈ 4 characters)
  int get tokenCount => (text.length / 4).ceil();

  Map<String, dynamic> toJson() => {
        'text': text,
        'embedding': embedding,
        'sentenceRange': sentenceRange != null
            ? [sentenceRange!.$1, sentenceRange!.$2]
            : null,
        'tokenCount': tokenCount,
      };

  @override
  String toString() {
    final preview = text.length > 50 ? '${text.substring(0, 47)}...' : text;
    return 'Chunk(text: "$preview", tokens: $tokenCount, range: $sentenceRange)';
  }
}

/// Chunks text by semantic similarity using embeddings
///
/// Algorithm:
/// 1. Split text into sentences
/// 2. Embed all sentences (batch for efficiency)
/// 3. Find chunk boundaries where similarity drops below threshold
/// 4. Mean-pool sentence embeddings to create chunk embeddings
///
/// This ensures:
/// - Semantic coherence (don't split mid-thought)
/// - Chunks are small enough for relevant retrieval
/// - No wasted embeddings (sentence embeddings are reused)
class SemanticChunker {
  final EmbeddingService _embeddingService;
  final SentenceSplitter _sentenceSplitter;

  /// Similarity threshold for chunk boundaries (0.0 to 1.0)
  ///
  /// When cosine similarity between adjacent sentences drops below this,
  /// a new chunk is created.
  ///
  /// - 0.3 = More aggressive splitting, smaller chunks
  /// - 0.5 = Balanced (default)
  /// - 0.7 = Conservative, larger chunks
  final double similarityThreshold;

  /// Maximum tokens per chunk (soft limit)
  ///
  /// If a chunk exceeds this, force-split at sentence boundary
  /// even if semantic similarity is high.
  final int maxChunkTokens;

  SemanticChunker(
    this._embeddingService, {
    this.similarityThreshold = 0.5,
    this.maxChunkTokens = 500,
  }) : _sentenceSplitter = SentenceSplitter();

  /// Chunk a transcript into semantic units
  ///
  /// Returns a list of chunks with pre-computed embeddings.
  /// Each chunk's embedding is the mean-pooled average of its sentence embeddings.
  Future<List<Chunk>> chunkTranscript(String transcript) async {
    debugPrint('[SemanticChunker] Chunking transcript of length: ${transcript.length}');

    // Step 1: Split into sentences
    final sentences = _sentenceSplitter.split(transcript);

    if (sentences.isEmpty) {
      debugPrint('[SemanticChunker] No sentences found, returning empty list');
      return [];
    }

    debugPrint('[SemanticChunker] Split into ${sentences.length} sentences');

    if (sentences.length == 1) {
      // Single sentence = single chunk
      debugPrint('[SemanticChunker] Single sentence, creating one chunk');
      final embedding = await _embeddingService.embed(sentences[0]);
      return [
        Chunk(
          text: sentences[0],
          embedding: embedding,
          sentenceRange: (0, 1),
        ),
      ];
    }

    // Step 2: Embed all sentences (batch for efficiency)
    debugPrint('[SemanticChunker] Embedding ${sentences.length} sentences...');
    final sentenceEmbeddings = await _embeddingService.embedBatch(sentences);
    debugPrint('[SemanticChunker] Embeddings complete');

    // Step 3: Find chunk boundaries
    final boundaries = _findBoundaries(sentences, sentenceEmbeddings);
    debugPrint('[SemanticChunker] Found ${boundaries.length} boundaries');

    // Step 4: Create chunks with mean-pooled embeddings
    final chunks = _createChunks(sentences, sentenceEmbeddings, boundaries);
    debugPrint('[SemanticChunker] Created ${chunks.length} chunks');

    return chunks;
  }

  /// Find chunk boundaries based on semantic similarity and size constraints
  List<int> _findBoundaries(
    List<String> sentences,
    List<List<double>> embeddings,
  ) {
    final boundaries = <int>[0]; // Always start at 0

    int currentChunkTokens = _estimateTokens(sentences[0]);

    for (int i = 1; i < embeddings.length; i++) {
      final sentenceTokens = _estimateTokens(sentences[i]);

      // Check if adding this sentence would exceed max tokens
      if (currentChunkTokens + sentenceTokens > maxChunkTokens) {
        // Force a boundary here due to size constraint
        debugPrint(
          '[SemanticChunker] Forcing boundary at sentence $i (token limit)',
        );
        boundaries.add(i);
        currentChunkTokens = sentenceTokens;
        continue;
      }

      // Check semantic similarity
      final similarity = _cosineSimilarity(embeddings[i - 1], embeddings[i]);

      if (similarity < similarityThreshold) {
        // Semantic boundary detected
        debugPrint(
          '[SemanticChunker] Boundary at sentence $i (similarity: ${similarity.toStringAsFixed(3)})',
        );
        boundaries.add(i);
        currentChunkTokens = sentenceTokens;
      } else {
        // Continue current chunk
        currentChunkTokens += sentenceTokens;
      }
    }

    return boundaries;
  }

  /// Create chunks from sentences and embeddings
  List<Chunk> _createChunks(
    List<String> sentences,
    List<List<double>> embeddings,
    List<int> boundaries,
  ) {
    final chunks = <Chunk>[];

    for (int i = 0; i < boundaries.length; i++) {
      final start = boundaries[i];
      final end = i + 1 < boundaries.length ? boundaries[i + 1] : sentences.length;

      final chunkSentences = sentences.sublist(start, end);
      final chunkEmbeddings = embeddings.sublist(start, end);

      chunks.add(Chunk(
        text: chunkSentences.join(' '),
        embedding: _meanPool(chunkEmbeddings),
        sentenceRange: (start, end),
      ));
    }

    return chunks;
  }

  /// Mean-pool multiple embeddings into one
  ///
  /// Takes the average of all embeddings and normalizes the result.
  List<double> _meanPool(List<List<double>> embeddings) {
    if (embeddings.isEmpty) return [];
    if (embeddings.length == 1) return embeddings[0];

    final dims = embeddings[0].length;
    final result = List<double>.filled(dims, 0.0);

    // Sum all embeddings
    for (final emb in embeddings) {
      for (int i = 0; i < dims; i++) {
        result[i] += emb[i];
      }
    }

    // Average
    for (int i = 0; i < dims; i++) {
      result[i] /= embeddings.length;
    }

    // Normalize to unit length
    return _normalize(result);
  }

  /// Normalize a vector to unit length (L2 norm = 1)
  List<double> _normalize(List<double> vector) {
    double sumSquares = 0.0;
    for (final value in vector) {
      sumSquares += value * value;
    }
    final magnitude = sqrt(sumSquares);

    // Avoid division by zero
    if (magnitude == 0.0) {
      return vector;
    }

    return vector.map((v) => v / magnitude).toList();
  }

  /// Calculate cosine similarity between two vectors
  ///
  /// Returns a value between -1 and 1:
  /// - 1.0 = identical direction (very similar)
  /// - 0.0 = orthogonal (unrelated)
  /// - -1.0 = opposite direction (very dissimilar)
  double _cosineSimilarity(List<double> a, List<double> b) {
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = sqrt(normA) * sqrt(normB);

    // Avoid division by zero
    if (denominator == 0.0) {
      return 0.0;
    }

    return dotProduct / denominator;
  }

  /// Estimate token count for a sentence (1 token ≈ 4 characters)
  int _estimateTokens(String text) {
    return (text.length / 4).ceil();
  }
}
