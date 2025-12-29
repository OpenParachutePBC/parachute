/// Source of a recording (phone microphone or Omi device)
enum RecordingSource {
  phone,
  omiDevice;

  @override
  String toString() {
    switch (this) {
      case RecordingSource.phone:
        return 'phone';
      case RecordingSource.omiDevice:
        return 'omiDevice';
    }
  }

  static RecordingSource fromString(String value) {
    switch (value.toLowerCase()) {
      case 'omidevice':
        return RecordingSource.omiDevice;
      case 'phone':
      default:
        return RecordingSource.phone;
    }
  }
}

/// Represents a segment within a recording (for appended recordings)
class RecordingSegment {
  /// End time of this segment in seconds (start is previous segment's end, or 0)
  final double endSeconds;

  /// When this segment was recorded
  final DateTime recorded;

  RecordingSegment({
    required this.endSeconds,
    required this.recorded,
  });

  Map<String, dynamic> toJson() => {
    'end': endSeconds,
    'recorded': recorded.toIso8601String(),
  };

  factory RecordingSegment.fromJson(Map<String, dynamic> json) =>
      RecordingSegment(
        endSeconds: (json['end'] as num?)?.toDouble() ?? 0.0,
        recorded:
            DateTime.tryParse(json['recorded'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Processing status for background tasks
enum ProcessingStatus {
  pending, // Not started
  processing, // In progress
  completed, // Successfully completed
  failed; // Failed with error

  @override
  String toString() {
    switch (this) {
      case ProcessingStatus.pending:
        return 'pending';
      case ProcessingStatus.processing:
        return 'processing';
      case ProcessingStatus.completed:
        return 'completed';
      case ProcessingStatus.failed:
        return 'failed';
    }
  }

  static ProcessingStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'processing':
        return ProcessingStatus.processing;
      case 'completed':
        return ProcessingStatus.completed;
      case 'failed':
        return ProcessingStatus.failed;
      case 'pending':
      default:
        return ProcessingStatus.pending;
    }
  }
}

class Recording {
  final String id;
  final String title;
  final String filePath;
  final DateTime timestamp;
  final Duration duration;
  final List<String> tags;
  final String transcript;
  final String context; // Additional notes/context about the recording
  final String summary; // AI-generated summary of the transcript
  final double fileSizeKB;
  final RecordingSource source;
  final String? deviceId; // Omi device ID if from device
  final int? buttonTapCount; // 1, 2, or 3 for device button taps

  // Processing status fields
  final ProcessingStatus transcriptionStatus;
  final ProcessingStatus titleGenerationStatus;
  final ProcessingStatus summaryStatus;

  // Live transcription status (for detecting incomplete transcriptions)
  final String? liveTranscriptionStatus; // 'in_progress', 'completed', null

  // Segments for recordings with multiple appended parts
  final List<RecordingSegment>? segments;

  Recording({
    required this.id,
    required this.title,
    required this.filePath,
    required this.timestamp,
    required this.duration,
    required this.tags,
    required this.transcript,
    this.context = '', // Default to empty string
    this.summary = '', // Default to empty string
    required this.fileSizeKB,
    this.source = RecordingSource.phone,
    this.deviceId,
    this.buttonTapCount,
    this.transcriptionStatus = ProcessingStatus.pending,
    this.titleGenerationStatus = ProcessingStatus.pending,
    this.summaryStatus = ProcessingStatus.pending,
    this.liveTranscriptionStatus,
    this.segments,
  }) : assert(id.isNotEmpty, 'Recording ID cannot be empty'),
       assert(title.isNotEmpty, 'Recording title cannot be empty'),
       assert(filePath.isNotEmpty, 'Recording file path cannot be empty'),
       assert(duration >= Duration.zero, 'Duration must be non-negative'),
       assert(fileSizeKB >= 0, 'File size must be non-negative'),
       assert(
         source == RecordingSource.phone ||
             (source == RecordingSource.omiDevice && deviceId != null),
         'Device ID required for omiDevice source',
       ),
       assert(
         buttonTapCount == null || (buttonTapCount >= 1 && buttonTapCount <= 3),
         'Button tap count must be 1, 2, or 3 if provided',
       );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filePath': filePath,
    'timestamp': timestamp.toIso8601String(),
    'duration': duration.inMilliseconds,
    'tags': tags,
    'transcript': transcript,
    'context': context,
    'summary': summary,
    'fileSizeKB': fileSizeKB,
    'source': source.toString(),
    'deviceId': deviceId,
    'buttonTapCount': buttonTapCount,
    'transcriptionStatus': transcriptionStatus.toString(),
    'titleGenerationStatus': titleGenerationStatus.toString(),
    'summaryStatus': summaryStatus.toString(),
    'liveTranscriptionStatus': liveTranscriptionStatus,
    'segments': segments?.map((s) => s.toJson()).toList(),
  };

  factory Recording.fromJson(Map<String, dynamic> json) => Recording(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? 'Untitled',
    filePath: json['filePath'] as String? ?? '',
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    duration: Duration(milliseconds: json['duration'] as int? ?? 0),
    tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    transcript: json['transcript'] as String? ?? '',
    context: json['context'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    fileSizeKB: (json['fileSizeKB'] as num?)?.toDouble() ?? 0.0,
    source: json['source'] != null
        ? RecordingSource.fromString(json['source'] as String)
        : RecordingSource.phone,
    deviceId: json['deviceId'] as String?,
    buttonTapCount: json['buttonTapCount'] as int?,
    transcriptionStatus: json['transcriptionStatus'] != null
        ? ProcessingStatus.fromString(json['transcriptionStatus'] as String)
        : ProcessingStatus.pending,
    titleGenerationStatus: json['titleGenerationStatus'] != null
        ? ProcessingStatus.fromString(json['titleGenerationStatus'] as String)
        : ProcessingStatus.pending,
    summaryStatus: json['summaryStatus'] != null
        ? ProcessingStatus.fromString(json['summaryStatus'] as String)
        : ProcessingStatus.pending,
    liveTranscriptionStatus: json['liveTranscriptionStatus'] as String?,
    segments: (json['segments'] as List<dynamic>?)
        ?.map((s) => RecordingSegment.fromJson(s as Map<String, dynamic>))
        .toList(),
  );

  String get durationString {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (fileSizeKB < 1024) {
      return '${fileSizeKB.toStringAsFixed(1)}KB';
    }
    return '${(fileSizeKB / 1024).toStringAsFixed(1)}MB';
  }

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  /// Helper method to check if transcription is incomplete
  bool get isTranscriptionIncomplete {
    return liveTranscriptionStatus == 'in_progress';
  }

  /// Create a copy with updated fields
  Recording copyWith({
    String? id,
    String? title,
    String? filePath,
    DateTime? timestamp,
    Duration? duration,
    List<String>? tags,
    String? transcript,
    String? context,
    String? summary,
    double? fileSizeKB,
    RecordingSource? source,
    String? deviceId,
    int? buttonTapCount,
    ProcessingStatus? transcriptionStatus,
    ProcessingStatus? titleGenerationStatus,
    ProcessingStatus? summaryStatus,
    String? liveTranscriptionStatus,
    List<RecordingSegment>? segments,
  }) {
    return Recording(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      timestamp: timestamp ?? this.timestamp,
      duration: duration ?? this.duration,
      tags: tags ?? this.tags,
      transcript: transcript ?? this.transcript,
      context: context ?? this.context,
      summary: summary ?? this.summary,
      fileSizeKB: fileSizeKB ?? this.fileSizeKB,
      source: source ?? this.source,
      deviceId: deviceId ?? this.deviceId,
      buttonTapCount: buttonTapCount ?? this.buttonTapCount,
      transcriptionStatus: transcriptionStatus ?? this.transcriptionStatus,
      titleGenerationStatus:
          titleGenerationStatus ?? this.titleGenerationStatus,
      summaryStatus: summaryStatus ?? this.summaryStatus,
      liveTranscriptionStatus:
          liveTranscriptionStatus ?? this.liveTranscriptionStatus,
      segments: segments ?? this.segments,
    );
  }
}
