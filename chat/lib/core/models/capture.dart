/// Capture/Note model for registry
class Capture {
  final String id;
  final String baseName;
  final String? title;
  final DateTime createdAt;
  final bool hasAudio;
  final bool hasTranscript;
  final String? metadata;

  Capture({
    required this.id,
    required this.baseName,
    this.title,
    required this.createdAt,
    required this.hasAudio,
    required this.hasTranscript,
    this.metadata,
  });

  factory Capture.fromJson(Map<String, dynamic> json) {
    return Capture(
      id: json['id'] as String,
      baseName: json['base_name'] as String,
      title: json['title'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      hasAudio: json['has_audio'] as bool,
      hasTranscript: json['has_transcript'] as bool,
      metadata: json['metadata'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'base_name': baseName,
      if (title != null) 'title': title,
      'created_at': createdAt.toIso8601String(),
      'has_audio': hasAudio,
      'has_transcript': hasTranscript,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

/// Parameters for adding a capture
class AddCaptureParams {
  final String baseName;
  final String? title;
  final bool hasAudio;
  final bool hasTranscript;
  final String? metadata;

  AddCaptureParams({
    required this.baseName,
    this.title,
    required this.hasAudio,
    required this.hasTranscript,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'base_name': baseName,
      if (title != null) 'title': title,
      'has_audio': hasAudio,
      'has_transcript': hasTranscript,
      if (metadata != null) 'metadata': metadata,
    };
  }
}
