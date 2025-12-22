import 'package:flutter/foundation.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/search/chunking/semantic_chunker.dart';
import 'package:app/core/services/search/models/indexed_chunk.dart';
import 'package:app/features/journal/models/journal_entry.dart';
import 'package:app/features/journal/models/journal_day.dart';

/// High-level service for chunking journal entries into IndexedChunk objects
///
/// This service handles the complete chunking pipeline for journals:
/// 1. Chunk the content using semantic boundaries
/// 2. Embed single-field content (title)
/// 3. Return IndexedChunk objects ready for database insertion
///
/// Example usage:
/// ```dart
/// final chunker = JournalChunker(embeddingService);
/// final chunks = await chunker.chunkJournalDay(journalDay);
/// // chunks is a List<IndexedChunk> ready to be indexed
/// ```
class JournalChunker {
  final EmbeddingService _embeddingService;
  final SemanticChunker _semanticChunker;

  JournalChunker(
    this._embeddingService, {
    double similarityThreshold = 0.5,
    int maxChunkTokens = 500,
  }) : _semanticChunker = SemanticChunker(
          _embeddingService,
          similarityThreshold: similarityThreshold,
          maxChunkTokens: maxChunkTokens,
        );

  /// Chunk a single journal entry
  ///
  /// Returns a list of IndexedChunk objects containing:
  /// - Content chunks (multiple, semantically segmented)
  /// - Title chunk (single, if present)
  ///
  /// The contentId uses format: "journal:{date}:{entryId}"
  Future<List<IndexedChunk>> chunkEntry(
    JournalEntry entry,
    DateTime date,
  ) async {
    // Skip preamble and plain markdown entries that don't have meaningful content
    if (entry.id == 'preamble' || entry.content.isEmpty) {
      return [];
    }

    final contentId = _makeContentId(date, entry.id);
    debugPrint('[JournalChunker] Chunking entry: $contentId');

    final chunks = <IndexedChunk>[];

    // 1. Chunk the content (main content)
    if (entry.content.isNotEmpty) {
      debugPrint('[JournalChunker] Chunking content...');
      final contentChunks = await _semanticChunker.chunkTranscript(
        entry.content,
      );

      for (int i = 0; i < contentChunks.length; i++) {
        chunks.add(IndexedChunk(
          recordingId: contentId,
          contentType: ContentType.journal,
          field: 'content',
          chunkIndex: i,
          chunkText: contentChunks[i].text,
          embedding: contentChunks[i].embedding,
        ));
      }

      debugPrint(
        '[JournalChunker] Created ${contentChunks.length} content chunks',
      );
    }

    // 2. Embed title as single chunk (short, semantically dense)
    if (entry.title.isNotEmpty) {
      debugPrint('[JournalChunker] Embedding title...');
      final titleEmbedding = await _embeddingService.embed(entry.title);
      chunks.add(IndexedChunk(
        recordingId: contentId,
        contentType: ContentType.journal,
        field: 'title',
        chunkIndex: 0,
        chunkText: entry.title,
        embedding: titleEmbedding,
      ));
    }

    debugPrint(
      '[JournalChunker] Entry $contentId indexed: ${chunks.length} total chunks',
    );

    return chunks;
  }

  /// Chunk all entries in a journal day
  ///
  /// Returns a list of IndexedChunk objects for all entries in the day.
  Future<List<IndexedChunk>> chunkJournalDay(JournalDay journal) async {
    debugPrint(
      '[JournalChunker] Chunking journal day: ${journal.dateString} '
      '(${journal.entryCount} entries)',
    );

    final allChunks = <IndexedChunk>[];

    for (final entry in journal.entries) {
      final chunks = await chunkEntry(entry, journal.date);
      allChunks.addAll(chunks);
    }

    debugPrint(
      '[JournalChunker] Journal day complete: ${allChunks.length} total chunks',
    );

    return allChunks;
  }

  /// Chunk multiple journal days in batch
  ///
  /// More efficient than calling [chunkJournalDay] multiple times
  /// for large-scale indexing operations.
  Future<List<IndexedChunk>> chunkJournalDays(
    List<JournalDay> journals,
  ) async {
    debugPrint(
      '[JournalChunker] Batch chunking ${journals.length} journal days...',
    );

    final allChunks = <IndexedChunk>[];

    for (final journal in journals) {
      final chunks = await chunkJournalDay(journal);
      allChunks.addAll(chunks);
    }

    debugPrint(
      '[JournalChunker] Batch complete: ${allChunks.length} total chunks',
    );

    return allChunks;
  }

  /// Create a unique content ID for a journal entry
  ///
  /// Format: "journal:YYYY-MM-DD:entryId"
  String _makeContentId(DateTime date, String entryId) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return 'journal:$dateStr:$entryId';
  }
}
