/// Result from a vector similarity search
class VectorSearchResult {
  /// Unique ID of the chunk
  final int chunkId;

  /// ID of the recording this chunk belongs to
  final String recordingId;

  /// Field this chunk came from ('transcript', 'title', 'summary', 'context')
  final String field;

  /// Index of this chunk within the field
  final int chunkIndex;

  /// The actual text content of the chunk
  final String chunkText;

  /// Cosine similarity score (0.0 to 1.0, higher is better)
  /// 1.0 = identical vectors
  /// 0.0 = orthogonal (no similarity)
  final double score;

  VectorSearchResult({
    required this.chunkId,
    required this.recordingId,
    required this.field,
    required this.chunkIndex,
    required this.chunkText,
    required this.score,
  });

  /// Create a copy with updated fields
  VectorSearchResult copyWith({
    int? chunkId,
    String? recordingId,
    String? field,
    int? chunkIndex,
    String? chunkText,
    double? score,
  }) {
    return VectorSearchResult(
      chunkId: chunkId ?? this.chunkId,
      recordingId: recordingId ?? this.recordingId,
      field: field ?? this.field,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      chunkText: chunkText ?? this.chunkText,
      score: score ?? this.score,
    );
  }

  @override
  String toString() {
    return 'VectorSearchResult(chunkId: $chunkId, recordingId: $recordingId, '
        'field: $field, score: ${score.toStringAsFixed(4)}, '
        'text: ${chunkText.substring(0, chunkText.length > 50 ? 50 : chunkText.length)}...)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VectorSearchResult &&
        other.chunkId == chunkId &&
        other.recordingId == recordingId &&
        other.field == field &&
        other.chunkIndex == chunkIndex &&
        other.score == score;
  }

  @override
  int get hashCode {
    return Object.hash(chunkId, recordingId, field, chunkIndex, score);
  }
}
