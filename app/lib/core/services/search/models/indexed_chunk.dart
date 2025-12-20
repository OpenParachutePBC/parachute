/// Represents a chunk of text that has been indexed with its embedding
class IndexedChunk {
  /// Unique ID for this chunk (auto-generated in DB)
  final int? id;

  /// ID of the recording this chunk belongs to
  final String recordingId;

  /// Field this chunk came from ('transcript', 'title', 'summary', 'context')
  final String field;

  /// Index of this chunk within the field (0-based)
  final int chunkIndex;

  /// The actual text content of the chunk
  final String chunkText;

  /// Pre-normalized embedding vector (256 dimensions)
  /// Stored as normalized for faster cosine similarity computation
  final List<double> embedding;

  /// When this chunk was created
  final DateTime createdAt;

  IndexedChunk({
    this.id,
    required this.recordingId,
    required this.field,
    required this.chunkIndex,
    required this.chunkText,
    required this.embedding,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now() {
    // Validate embedding dimensions
    if (embedding.length != 256) {
      throw ArgumentError(
        'Embedding must be 256 dimensions, got ${embedding.length}',
      );
    }
  }

  /// Create a copy with updated fields
  IndexedChunk copyWith({
    int? id,
    String? recordingId,
    String? field,
    int? chunkIndex,
    String? chunkText,
    List<double>? embedding,
    DateTime? createdAt,
  }) {
    return IndexedChunk(
      id: id ?? this.id,
      recordingId: recordingId ?? this.recordingId,
      field: field ?? this.field,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      chunkText: chunkText ?? this.chunkText,
      embedding: embedding ?? this.embedding,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'IndexedChunk(id: $id, recordingId: $recordingId, field: $field, '
        'chunkIndex: $chunkIndex, text: ${chunkText.substring(0, chunkText.length > 50 ? 50 : chunkText.length)}...)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IndexedChunk &&
        other.id == id &&
        other.recordingId == recordingId &&
        other.field == field &&
        other.chunkIndex == chunkIndex;
  }

  @override
  int get hashCode {
    return Object.hash(id, recordingId, field, chunkIndex);
  }
}
