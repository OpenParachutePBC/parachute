import 'package:flutter/foundation.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/search/chunking/semantic_chunker.dart';
import 'package:app/core/services/search/models/indexed_chunk.dart';
import 'package:app/features/recorder/models/recording.dart';

/// High-level service for chunking recordings into IndexedChunk objects
///
/// This service handles the complete chunking pipeline:
/// 1. Chunk the transcript using semantic boundaries
/// 2. Embed single-field content (title, summary, context)
/// 3. Return IndexedChunk objects ready for database insertion
///
/// Example usage:
/// ```dart
/// final chunker = RecordingChunker(embeddingService);
/// final chunks = await chunker.chunkRecording(recording);
/// // chunks is a List<IndexedChunk> ready to be indexed
/// ```
class RecordingChunker {
  final EmbeddingService _embeddingService;
  final SemanticChunker _semanticChunker;

  RecordingChunker(
    this._embeddingService, {
    double similarityThreshold = 0.5,
    int maxChunkTokens = 500,
  }) : _semanticChunker = SemanticChunker(
          _embeddingService,
          similarityThreshold: similarityThreshold,
          maxChunkTokens: maxChunkTokens,
        );

  /// Chunk all searchable content from a recording
  ///
  /// Returns a list of IndexedChunk objects containing:
  /// - Transcript chunks (multiple, semantically segmented)
  /// - Title chunk (single)
  /// - Summary chunk (single, if present)
  /// - Context chunk (single, if present)
  ///
  /// All embeddings are pre-computed and normalized.
  Future<List<IndexedChunk>> chunkRecording(Recording recording) async {
    debugPrint('[RecordingChunker] Chunking recording: ${recording.id}');

    final chunks = <IndexedChunk>[];

    // 1. Chunk the transcript (main content)
    if (recording.transcript.isNotEmpty) {
      debugPrint('[RecordingChunker] Chunking transcript...');
      final transcriptChunks = await _semanticChunker.chunkTranscript(
        recording.transcript,
      );

      for (int i = 0; i < transcriptChunks.length; i++) {
        chunks.add(IndexedChunk(
          recordingId: recording.id,
          field: 'transcript',
          chunkIndex: i,
          chunkText: transcriptChunks[i].text,
          embedding: transcriptChunks[i].embedding,
        ));
      }

      debugPrint(
        '[RecordingChunker] Created ${transcriptChunks.length} transcript chunks',
      );
    }

    // 2. Embed title as single chunk (short, semantically dense)
    if (recording.title.isNotEmpty) {
      debugPrint('[RecordingChunker] Embedding title...');
      final titleEmbedding = await _embeddingService.embed(recording.title);
      chunks.add(IndexedChunk(
        recordingId: recording.id,
        field: 'title',
        chunkIndex: 0,
        chunkText: recording.title,
        embedding: titleEmbedding,
      ));
    }

    // 3. Embed summary as single chunk (if present)
    if (recording.summary.isNotEmpty) {
      debugPrint('[RecordingChunker] Embedding summary...');
      final summaryEmbedding = await _embeddingService.embed(recording.summary);
      chunks.add(IndexedChunk(
        recordingId: recording.id,
        field: 'summary',
        chunkIndex: 0,
        chunkText: recording.summary,
        embedding: summaryEmbedding,
      ));
    }

    // 4. Embed context as single chunk (if present)
    if (recording.context.isNotEmpty) {
      debugPrint('[RecordingChunker] Embedding context...');
      final contextEmbedding = await _embeddingService.embed(recording.context);
      chunks.add(IndexedChunk(
        recordingId: recording.id,
        field: 'context',
        chunkIndex: 0,
        chunkText: recording.context,
        embedding: contextEmbedding,
      ));
    }

    debugPrint(
      '[RecordingChunker] ✅ Chunking complete: ${chunks.length} total chunks',
    );

    return chunks;
  }

  /// Chunk multiple recordings in batch
  ///
  /// More efficient than calling [chunkRecording] multiple times
  /// for large-scale indexing operations.
  Future<List<IndexedChunk>> chunkRecordings(
    List<Recording> recordings,
  ) async {
    debugPrint(
      '[RecordingChunker] Batch chunking ${recordings.length} recordings...',
    );

    final allChunks = <IndexedChunk>[];

    for (final recording in recordings) {
      final chunks = await chunkRecording(recording);
      allChunks.addAll(chunks);
    }

    debugPrint(
      '[RecordingChunker] ✅ Batch complete: ${allChunks.length} total chunks',
    );

    return allChunks;
  }
}
