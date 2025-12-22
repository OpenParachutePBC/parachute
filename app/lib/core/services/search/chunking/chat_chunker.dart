import 'package:flutter/foundation.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/search/chunking/semantic_chunker.dart';
import 'package:app/core/services/search/models/indexed_chunk.dart';
import 'package:app/features/chat/services/local_session_reader.dart';

/// High-level service for chunking chat sessions into IndexedChunk objects
///
/// This service handles the complete chunking pipeline for chat sessions:
/// 1. Chunk the conversation using semantic boundaries
/// 2. Embed metadata (title)
/// 3. Return IndexedChunk objects ready for database insertion
///
/// Example usage:
/// ```dart
/// final chunker = ChatChunker(embeddingService);
/// final chunks = await chunker.chunkChatSession(sessionWithMessages);
/// // chunks is a List<IndexedChunk> ready to be indexed
/// ```
class ChatChunker {
  final EmbeddingService _embeddingService;
  final SemanticChunker _semanticChunker;

  ChatChunker(
    this._embeddingService, {
    double similarityThreshold = 0.5,
    int maxChunkTokens = 500,
  }) : _semanticChunker = SemanticChunker(
          _embeddingService,
          similarityThreshold: similarityThreshold,
          maxChunkTokens: maxChunkTokens,
        );

  /// Chunk a chat session with its messages
  ///
  /// Returns a list of IndexedChunk objects containing:
  /// - Conversation chunks (multiple, semantically segmented)
  /// - Title chunk (single, if present)
  ///
  /// The contentId uses format: "chat:{sessionId}"
  Future<List<IndexedChunk>> chunkChatSession(
    ChatSessionWithLocalMessages sessionData,
    String sourcePath,
  ) async {
    final session = sessionData.session;
    final messages = sessionData.messages;

    if (messages.isEmpty) {
      return [];
    }

    final contentId = 'chat:${session.id}';
    debugPrint('[ChatChunker] Chunking session: $contentId');

    final chunks = <IndexedChunk>[];

    // 1. Combine messages into a conversation transcript
    final conversationBuffer = StringBuffer();
    for (final message in messages) {
      final roleLabel = message.role.name.toUpperCase();
      conversationBuffer.writeln('$roleLabel: ${message.textContent}');
      conversationBuffer.writeln();
    }
    final conversation = conversationBuffer.toString().trim();

    // 2. Chunk the conversation
    if (conversation.isNotEmpty) {
      debugPrint('[ChatChunker] Chunking conversation...');
      final conversationChunks = await _semanticChunker.chunkTranscript(
        conversation,
      );

      for (int i = 0; i < conversationChunks.length; i++) {
        chunks.add(IndexedChunk(
          recordingId: contentId,
          contentType: ContentType.chat,
          field: 'conversation',
          chunkIndex: i,
          chunkText: conversationChunks[i].text,
          embedding: conversationChunks[i].embedding,
        ));
      }

      debugPrint(
        '[ChatChunker] Created ${conversationChunks.length} conversation chunks',
      );
    }

    // 3. Embed title as single chunk (short, semantically dense)
    final title = session.title ?? session.displayTitle;
    if (title.isNotEmpty) {
      debugPrint('[ChatChunker] Embedding title...');
      final titleEmbedding = await _embeddingService.embed(title);
      chunks.add(IndexedChunk(
        recordingId: contentId,
        contentType: ContentType.chat,
        field: 'title',
        chunkIndex: 0,
        chunkText: title,
        embedding: titleEmbedding,
      ));
    }

    debugPrint(
      '[ChatChunker] Session $contentId indexed: ${chunks.length} total chunks',
    );

    return chunks;
  }

  /// Chunk multiple chat sessions in batch
  ///
  /// More efficient than calling [chunkChatSession] multiple times
  /// for large-scale indexing operations.
  Future<List<IndexedChunk>> chunkChatSessions(
    List<(ChatSessionWithLocalMessages, String)> sessionsWithPaths,
  ) async {
    debugPrint(
      '[ChatChunker] Batch chunking ${sessionsWithPaths.length} chat sessions...',
    );

    final allChunks = <IndexedChunk>[];

    for (final (sessionData, sourcePath) in sessionsWithPaths) {
      final chunks = await chunkChatSession(sessionData, sourcePath);
      allChunks.addAll(chunks);
    }

    debugPrint(
      '[ChatChunker] Batch complete: ${allChunks.length} total chunks',
    );

    return allChunks;
  }
}
