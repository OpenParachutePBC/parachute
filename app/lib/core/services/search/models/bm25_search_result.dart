import 'package:app/features/recorder/models/recording.dart';

/// Result from a BM25 keyword search
///
/// Contains the matched recording, BM25 relevance score, and which fields
/// matched the search query (for highlighting in UI).
class BM25SearchResult {
  /// The recording that matched the search
  final Recording recording;

  /// BM25 relevance score (higher = more relevant)
  /// Typically ranges from 0 to ~10, but can be higher for very relevant matches
  final double score;

  /// Fields that contained search terms
  /// Possible values: title, summary, context, transcript, tags
  final Set<String> matchedFields;

  BM25SearchResult({
    required this.recording,
    required this.score,
    required this.matchedFields,
  });

  @override
  String toString() {
    return 'BM25SearchResult(id: ${recording.id}, score: ${score.toStringAsFixed(2)}, '
        'fields: ${matchedFields.join(", ")})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BM25SearchResult &&
        other.recording.id == recording.id &&
        other.score == score &&
        other.matchedFields.length == matchedFields.length &&
        other.matchedFields.containsAll(matchedFields);
  }

  @override
  int get hashCode => Object.hash(
        recording.id,
        score,
        matchedFields.length,
      );
}
