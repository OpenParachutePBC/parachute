import 'package:flutter/foundation.dart';
import 'package:app/core/services/search/vector_store.dart';
import 'package:app/core/services/search/models/indexed_chunk.dart';
import 'package:app/core/services/search/models/vector_search_result.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/local_llm_service.dart';
import 'package:app/features/ask/models/ask_result.dart';

/// Service for answering questions about journal entries using RAG
///
/// Flow:
/// 1. Embed the user's question
/// 2. Search vector store for relevant journal chunks
/// 3. Build context from search results
/// 4. Generate answer using local LLM
class AskService {
  final VectorStore _vectorStore;
  final EmbeddingService _embeddingService;
  final LocalLlmService _llmService;

  AskService({
    required VectorStore vectorStore,
    required EmbeddingService embeddingService,
    required LocalLlmService llmService,
  })  : _vectorStore = vectorStore,
        _embeddingService = embeddingService,
        _llmService = llmService;

  /// Ask a question about journal entries
  ///
  /// Returns an [AskResult] with the generated answer and source excerpts.
  /// Returns null if the question is empty or no relevant content is found.
  Future<AskResult?> askQuestion(
    String question, {
    int maxSources = 5,
    double minScore = 0.3,
  }) async {
    if (question.trim().isEmpty) {
      return null;
    }

    final startTime = DateTime.now();

    try {
      debugPrint('[AskService] Processing question: $question');

      // 1. Embed the question
      debugPrint('[AskService] Embedding question...');
      final queryEmbedding = await _embeddingService.embed(question);

      // 2. Search for relevant journal chunks
      debugPrint('[AskService] Searching journals...');
      final searchResults = await _vectorStore.search(
        queryEmbedding,
        limit: maxSources,
        minScore: minScore,
        filterContentType: ContentType.journal,
      );

      if (searchResults.isEmpty) {
        debugPrint('[AskService] No relevant journal entries found');
        return AskResult(
          answer: "I couldn't find any relevant information in your journals.",
          sources: [],
          duration: DateTime.now().difference(startTime),
        );
      }

      debugPrint('[AskService] Found ${searchResults.length} relevant chunks');

      // 3. Build context from search results
      final context = _buildContext(searchResults);
      debugPrint('[AskService] Built context (${context.length} chars)');

      // 4. Generate answer using LLM
      debugPrint('[AskService] Generating answer...');
      final answer = await _llmService.generateAnswer(
        question,
        journalContext: context,
      );

      final duration = DateTime.now().difference(startTime);
      debugPrint('[AskService] Answer generated in ${duration.inMilliseconds}ms');

      return AskResult(
        answer: answer ?? "I couldn't generate an answer. Please try again.",
        sources: searchResults,
        duration: duration,
      );
    } catch (e, stackTrace) {
      debugPrint('[AskService] Error: $e');
      debugPrint('[AskService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Build context string from search results
  ///
  /// Formats each result with its date and content for the LLM prompt.
  String _buildContext(List<VectorSearchResult> results) {
    final buffer = StringBuffer();

    for (final result in results) {
      // Parse date from recordingId (format: journal:YYYY-MM-DD:entryId)
      final date = _parseDateFromRecordingId(result.recordingId);
      final dateStr = date != null
          ? '${_monthName(date.month)} ${date.day}, ${date.year}'
          : 'Unknown date';

      buffer.writeln('--- Journal Entry ($dateStr) ---');
      buffer.writeln(result.chunkText.trim());
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Parse date from journal recordingId
  ///
  /// Format: journal:YYYY-MM-DD:entryId
  DateTime? _parseDateFromRecordingId(String recordingId) {
    try {
      final parts = recordingId.split(':');
      if (parts.length >= 2 && parts[0] == 'journal') {
        return DateTime.parse(parts[1]);
      }
    } catch (e) {
      debugPrint('[AskService] Failed to parse date from $recordingId: $e');
    }
    return null;
  }

  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  /// Check if the service is ready to answer questions
  ///
  /// Requires both embedding model and LLM to be available.
  Future<bool> isReady() async {
    try {
      final embeddingReady = await _embeddingService.isReady();
      // TODO: Add LLM readiness check when available
      return embeddingReady;
    } catch (e) {
      return false;
    }
  }
}
