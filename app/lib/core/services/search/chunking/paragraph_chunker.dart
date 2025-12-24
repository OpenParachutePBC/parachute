import 'package:flutter/foundation.dart';
import 'package:app/core/services/embedding/embedding_service.dart';

/// A chunk of text with its embedding
class ParagraphChunk {
  /// The text content of this chunk
  final String text;

  /// Pre-computed embedding vector (normalized)
  final List<double> embedding;

  ParagraphChunk({
    required this.text,
    required this.embedding,
  });

  /// Approximate token count (rough estimate: 1 token ≈ 4 characters)
  int get tokenCount => (text.length / 4).ceil();
}

/// Simple paragraph-based chunker
///
/// Chunks text by splitting on paragraph boundaries (`\n\n`).
/// Much faster than semantic chunking because it doesn't need to
/// embed sentences just to find boundaries.
///
/// **Algorithm:**
/// 1. Split text on `\n\n` (paragraphs)
/// 2. Merge small paragraphs together until reaching target size
/// 3. Split oversized paragraphs on sentence boundaries
/// 4. Embed each final chunk once
///
/// **Benefits:**
/// - ~10x faster than semantic chunking (no sentence embeddings)
/// - Lower battery usage on mobile
/// - Still produces good results for retrieval
/// - Natural boundary detection (humans write in paragraphs)
class ParagraphChunker {
  final EmbeddingService _embeddingService;

  /// Target chunk size in tokens
  final int targetChunkTokens;

  /// Maximum chunk size in tokens (hard limit)
  final int maxChunkTokens;

  /// Minimum chunk size in tokens (merge if smaller)
  final int minChunkTokens;

  ParagraphChunker(
    this._embeddingService, {
    this.targetChunkTokens = 300,
    this.maxChunkTokens = 500,
    this.minChunkTokens = 50,
  });

  /// Chunk text into paragraph-based units with embeddings
  Future<List<ParagraphChunk>> chunkText(String text) async {
    if (text.trim().isEmpty) {
      return [];
    }

    debugPrint('[ParagraphChunker] Chunking text of length: ${text.length}');

    // Step 1: Split into paragraphs
    final paragraphs = _splitParagraphs(text);
    debugPrint('[ParagraphChunker] Split into ${paragraphs.length} paragraphs');

    if (paragraphs.isEmpty) {
      return [];
    }

    // Step 2: Merge small paragraphs and split large ones
    final chunks = _balanceChunks(paragraphs);
    debugPrint('[ParagraphChunker] Balanced to ${chunks.length} chunks');

    if (chunks.isEmpty) {
      return [];
    }

    // Step 3: Embed each chunk
    debugPrint('[ParagraphChunker] Embedding ${chunks.length} chunks...');
    final embeddings = await _embeddingService.embedBatch(chunks);

    // Step 4: Create chunk objects
    final result = <ParagraphChunk>[];
    for (int i = 0; i < chunks.length; i++) {
      result.add(ParagraphChunk(
        text: chunks[i],
        embedding: embeddings[i],
      ));
    }

    debugPrint('[ParagraphChunker] Created ${result.length} chunks');
    return result;
  }

  /// Split text into paragraphs (on double newlines)
  List<String> _splitParagraphs(String text) {
    // Normalize newlines and split on paragraph breaks
    final normalized = text.replaceAll('\r\n', '\n');

    // Split on double newlines (paragraph breaks)
    final paragraphs = normalized
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    return paragraphs;
  }

  /// Balance chunks by merging small ones and splitting large ones
  List<String> _balanceChunks(List<String> paragraphs) {
    final result = <String>[];
    final buffer = StringBuffer();
    int bufferTokens = 0;

    for (final para in paragraphs) {
      final paraTokens = _estimateTokens(para);

      // If this paragraph alone exceeds max, split it
      if (paraTokens > maxChunkTokens) {
        // Flush buffer first
        if (buffer.isNotEmpty) {
          result.add(buffer.toString().trim());
          buffer.clear();
          bufferTokens = 0;
        }

        // Split large paragraph on sentences
        final sentences = _splitSentences(para);
        final sentenceChunks = _mergeSentences(sentences);
        result.addAll(sentenceChunks);
        continue;
      }

      // Check if adding this paragraph exceeds target
      if (bufferTokens + paraTokens > targetChunkTokens && bufferTokens >= minChunkTokens) {
        // Flush buffer and start new chunk
        result.add(buffer.toString().trim());
        buffer.clear();
        bufferTokens = 0;
      }

      // Add paragraph to buffer
      if (buffer.isNotEmpty) {
        buffer.write('\n\n');
      }
      buffer.write(para);
      bufferTokens += paraTokens;
    }

    // Flush remaining buffer
    if (buffer.isNotEmpty) {
      result.add(buffer.toString().trim());
    }

    return result;
  }

  /// Split text into sentences (basic splitting)
  List<String> _splitSentences(String text) {
    // Split on sentence-ending punctuation followed by space or newline
    final pattern = RegExp(r'(?<=[.!?])\s+');
    return text
        .split(pattern)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Merge sentences into chunks of appropriate size
  List<String> _mergeSentences(List<String> sentences) {
    final result = <String>[];
    final buffer = StringBuffer();
    int bufferTokens = 0;

    for (final sentence in sentences) {
      final sentenceTokens = _estimateTokens(sentence);

      // Check if adding this sentence exceeds target
      if (bufferTokens + sentenceTokens > targetChunkTokens && bufferTokens >= minChunkTokens) {
        result.add(buffer.toString().trim());
        buffer.clear();
        bufferTokens = 0;
      }

      // Add sentence to buffer
      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write(sentence);
      bufferTokens += sentenceTokens;
    }

    // Flush remaining buffer
    if (buffer.isNotEmpty) {
      result.add(buffer.toString().trim());
    }

    return result;
  }

  /// Estimate token count (1 token ≈ 4 characters)
  int _estimateTokens(String text) {
    return (text.length / 4).ceil();
  }
}
