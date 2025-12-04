import 'package:app/features/recorder/models/recording.dart';

/// Unified search result from hybrid search
///
/// Combines vector (semantic) and BM25 (keyword) search results using
/// Reciprocal Rank Fusion (RRF) scoring. Provides rich metadata about
/// what matched and how relevant it is.
///
/// **Score Interpretation:**
/// - RRF scores typically range from 0.01 to 0.10
/// - Higher scores = more relevant
/// - Scores combine rankings from both search methods
/// - Documents ranking high in both searches get highest scores
///
/// **Example:**
/// ```dart
/// final result = SearchResult(
///   recording: recording,
///   matchedChunk: "discussed project alpha timeline",
///   matchedField: "transcript",
///   matchedFields: {"transcript", "title"},
///   rrfScore: 0.0320,
///   vectorScore: 0.85,
///   keywordScore: 8.2,
/// );
///
/// print(result.relevanceLabel); // "High relevance"
/// print(result.isBothMatch);    // true (found by both searches)
/// ```
class SearchResult {
  /// The matched recording
  final Recording recording;

  /// The specific chunk that matched (for highlighting)
  ///
  /// For vector search results, this is the specific chunk of text that
  /// had high semantic similarity. For BM25-only results, this may be null
  /// since BM25 searches the full recording.
  final String? matchedChunk;

  /// Which field the chunk came from
  ///
  /// Possible values:
  /// - 'transcript' - Main recording transcript
  /// - 'title' - Recording title
  /// - 'summary' - AI-generated summary
  /// - 'context' - User-provided context notes
  /// - 'full' - Full recording (BM25 match, not chunk-specific)
  final String matchedField;

  /// Which fields matched in keyword search
  ///
  /// Set of field names that contained search terms.
  /// Empty if this is a vector-only match.
  /// Useful for highlighting multiple matching fields in UI.
  final Set<String> matchedFields;

  /// Combined RRF score (higher = more relevant)
  ///
  /// Reciprocal Rank Fusion score combining vector and keyword rankings.
  /// Typical range: 0.01 to 0.10
  ///
  /// Formula: RRF_score = Σ 1/(k + rank) where k=60
  final double rrfScore;

  /// Individual vector similarity score (0.0 to 1.0)
  ///
  /// Null if not found by vector search.
  /// 1.0 = identical vectors, 0.0 = no similarity
  final double? vectorScore;

  /// Individual BM25 relevance score
  ///
  /// Null if not found by keyword search.
  /// Unbounded (typically 0-10, but can be higher for very relevant matches)
  final double? keywordScore;

  /// Rank in vector search results (0-based)
  ///
  /// Null if not found by vector search.
  /// Lower rank = higher position in results
  final int? vectorRank;

  /// Rank in BM25 search results (0-based)
  ///
  /// Null if not found by keyword search.
  /// Lower rank = higher position in results
  final int? keywordRank;

  SearchResult({
    required this.recording,
    this.matchedChunk,
    required this.matchedField,
    required this.matchedFields,
    required this.rrfScore,
    this.vectorScore,
    this.keywordScore,
    this.vectorRank,
    this.keywordRank,
  });

  /// Human-readable relevance label (for display)
  String get relevanceLabel {
    if (rrfScore > 0.03) return 'High relevance';
    if (rrfScore > 0.02) return 'Medium relevance';
    return 'Low relevance';
  }

  /// Was this found by vector search?
  bool get hasVectorMatch => vectorScore != null;

  /// Was this found by keyword search?
  bool get hasKeywordMatch => keywordScore != null;

  /// Found by both searches (strongest signal)
  ///
  /// Results found by both vector and keyword search are typically
  /// the most relevant, as they satisfy both semantic similarity
  /// and exact term matching.
  bool get isBothMatch => hasVectorMatch && hasKeywordMatch;

  /// Get a snippet of matched text for display
  ///
  /// Returns the matched chunk (truncated if needed), or a snippet
  /// from the transcript if no chunk is available.
  String getSnippet({int maxLength = 150}) {
    if (matchedChunk != null && matchedChunk!.isNotEmpty) {
      if (matchedChunk!.length <= maxLength) {
        return matchedChunk!;
      }
      return '${matchedChunk!.substring(0, maxLength)}...';
    }

    // Fallback to transcript snippet
    if (recording.transcript.isNotEmpty) {
      if (recording.transcript.length <= maxLength) {
        return recording.transcript;
      }
      return '${recording.transcript.substring(0, maxLength)}...';
    }

    return '';
  }

  @override
  String toString() {
    return 'SearchResult('
        'id: ${recording.id}, '
        'rrfScore: ${rrfScore.toStringAsFixed(4)}, '
        'field: $matchedField, '
        'vectorScore: ${vectorScore?.toStringAsFixed(4) ?? "null"}, '
        'keywordScore: ${keywordScore?.toStringAsFixed(2) ?? "null"}, '
        'isBothMatch: $isBothMatch'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SearchResult &&
        other.recording.id == recording.id &&
        other.matchedChunk == matchedChunk &&
        other.matchedField == matchedField &&
        other.rrfScore == rrfScore;
  }

  @override
  int get hashCode {
    return Object.hash(
      recording.id,
      matchedChunk,
      matchedField,
      rrfScore,
    );
  }
}
