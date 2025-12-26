import 'package:app/core/services/search/models/vector_search_result.dart';

/// Result from an Ask query
///
/// Contains the generated answer and the source journal excerpts
/// that were used to generate it.
class AskResult {
  /// The generated answer from the LLM
  final String answer;

  /// Source journal excerpts used to generate the answer
  ///
  /// Each result contains the chunk text and metadata (date, para ID)
  /// that can be used to navigate to the source.
  final List<VectorSearchResult> sources;

  /// How long the generation took
  final Duration? duration;

  AskResult({
    required this.answer,
    required this.sources,
    this.duration,
  });

  /// Check if any sources were found
  bool get hasSources => sources.isNotEmpty;

  /// Get a summary of sources for display
  String get sourceSummary {
    if (sources.isEmpty) return 'No sources';
    if (sources.length == 1) return '1 source';
    return '${sources.length} sources';
  }

  @override
  String toString() {
    return 'AskResult(answer: ${answer.length} chars, sources: ${sources.length}, duration: ${duration?.inMilliseconds}ms)';
  }
}

/// A message in an Ask session (question or answer)
class AskMessage {
  /// Unique ID for this message
  final String id;

  /// The message role
  final AskMessageRole role;

  /// The message content
  final String content;

  /// When the message was created
  final DateTime timestamp;

  /// Sources for assistant messages (null for user messages)
  final List<VectorSearchResult>? sources;

  AskMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.sources,
  });

  bool get isUser => role == AskMessageRole.user;
  bool get isAssistant => role == AskMessageRole.assistant;

  /// Create a user message
  factory AskMessage.user(String content) {
    return AskMessage(
      id: _generateId(),
      role: AskMessageRole.user,
      content: content,
      timestamp: DateTime.now(),
    );
  }

  /// Create an assistant message with sources
  factory AskMessage.assistant(String content, List<VectorSearchResult> sources) {
    return AskMessage(
      id: _generateId(),
      role: AskMessageRole.assistant,
      content: content,
      timestamp: DateTime.now(),
      sources: sources,
    );
  }

  static String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  }
}

enum AskMessageRole {
  user,
  assistant,
}
