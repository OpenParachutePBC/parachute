import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:app/features/recorder/services/live_transcription_service_v3.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:path/path.dart' as path;

/// Background transcription manager
///
/// Keeps transcription running even when UI screens are disposed.
/// Automatically saves results when transcription completes.
class BackgroundTranscriptionService {
  StreamSubscription? _subscription;
  AutoPauseTranscriptionService? _activeService;
  String? _timestamp;
  Duration? _duration;
  String? _capturesPath;

  // Callbacks for external listeners
  final List<Function(TranscriptionSegment)> _segmentListeners = [];
  final List<Function(bool)> _completionListeners = [];

  // Callback for when a file is saved (used to trigger UI refresh)
  Function()? onFileSaved;

  /// Start monitoring a transcription service in the background
  void startMonitoring({
    required AutoPauseTranscriptionService service,
    required String timestamp,
    required String audioPath,
    required Duration duration,
    required String capturesPath,
  }) {
    debugPrint('[BackgroundTranscription] Starting monitoring for $timestamp');

    // Clean up any existing subscription
    _subscription?.cancel();

    _activeService = service;
    _timestamp = timestamp;
    // audioPath is passed but not needed after monitoring starts
    _duration = duration;
    _capturesPath = capturesPath;

    // Listen to segment updates
    _subscription = service.segmentStream.listen(_handleSegmentUpdate);
  }

  void _handleSegmentUpdate(TranscriptionSegment segment) {
    debugPrint(
      '[BackgroundTranscription] Segment update: ${segment.index} - ${segment.status}',
    );

    // Notify all listeners (even if empty - service is still working!)
    debugPrint(
      '[BackgroundTranscription] Active listeners: ${_segmentListeners.length}',
    );
    for (final listener in _segmentListeners) {
      listener(segment);
    }

    // Check if transcription is complete
    final allSegments = _activeService?.segments ?? [];
    final completedCount = allSegments
        .where((s) => s.status == TranscriptionSegmentStatus.completed)
        .length;
    final hasIncomplete = allSegments.any(
      (s) =>
          s.status == TranscriptionSegmentStatus.pending ||
          s.status == TranscriptionSegmentStatus.processing,
    );

    debugPrint(
      '[BackgroundTranscription] Progress: $completedCount/${allSegments.length} segments complete',
    );

    if (!hasIncomplete && allSegments.isNotEmpty) {
      debugPrint(
        '[BackgroundTranscription] ✅ All segments complete! Saving file...',
      );
      _saveCompletedTranscription();
    }
  }

  Future<void> _saveCompletedTranscription() async {
    if (_activeService == null || _timestamp == null || _capturesPath == null) {
      debugPrint('[BackgroundTranscription] Missing required data for save');
      return;
    }

    try {
      // Calculate month folder path from timestamp
      final month = FileSystemService.getMonthFromRecordingId(_timestamp!);
      final monthPath = path.join(_capturesPath!, month);

      // Ensure month folder exists
      final monthDir = Directory(monthPath);
      if (!await monthDir.exists()) {
        await monthDir.create(recursive: true);
        debugPrint('[BackgroundTranscription] Created month folder: $monthPath');
      }

      final markdownPath = path.join(monthPath, '$_timestamp.md');

      // Read existing file to preserve created timestamp and title
      DateTime createdTime = DateTime.now();
      String title = 'Untitled Recording';
      String context = '';

      if (await File(markdownPath).exists()) {
        try {
          final existingContent = await File(markdownPath).readAsString();
          final lines = existingContent.split('\n');

          for (final line in lines) {
            if (line.startsWith('created:')) {
              final timeStr = line.substring('created:'.length).trim();
              createdTime = DateTime.tryParse(timeStr) ?? DateTime.now();
            }
            if (line.startsWith('title:')) {
              title = line.substring('title:'.length).trim();
            }
          }

          // Extract context if it exists
          final contextMatch = RegExp(
            r'## Context\n\n(.*?)\n\n',
            dotAll: true,
          ).firstMatch(existingContent);
          if (contextMatch != null) {
            context = contextMatch.group(1) ?? '';
          }
        } catch (e) {
          debugPrint(
            '[BackgroundTranscription] Could not read existing file: $e',
          );
        }
      }

      // Get complete transcript
      final fullTranscript = _activeService!.getCombinedText();

      // Create updated metadata
      final metadata = StringBuffer();
      metadata.writeln('---');
      metadata.writeln('title: $title');
      metadata.writeln('created: ${createdTime.toIso8601String()}');
      metadata.writeln('duration: ${_duration?.inSeconds ?? 0}');
      metadata.writeln(
        'words: ${fullTranscript.trim().isEmpty ? 0 : fullTranscript.trim().split(RegExp(r'\\s+')).length}',
      );
      metadata.writeln('source: live_recording');
      metadata.writeln('transcription_status: completed');
      metadata.writeln('---');
      metadata.writeln();
      metadata.writeln('# $title');
      metadata.writeln();

      if (context.isNotEmpty) {
        metadata.writeln('## Context');
        metadata.writeln();
        metadata.writeln(context);
        metadata.writeln();
      }

      if (fullTranscript.isNotEmpty) {
        metadata.writeln('## Transcription');
        metadata.writeln();
        metadata.writeln(fullTranscript);
      }

      // Save file
      await File(markdownPath).writeAsString(metadata.toString());
      debugPrint(
        '[BackgroundTranscription] ✅ Saved complete transcription: $markdownPath',
      );

      // Notify completion listeners
      for (final listener in _completionListeners) {
        listener(true);
      }

      // Trigger UI refresh callback (for HomeScreen to reload recordings list)
      if (onFileSaved != null) {
        debugPrint('[BackgroundTranscription] Triggering UI refresh callback');
        onFileSaved!();
      }

      // Clean up
      stopMonitoring();
    } catch (e) {
      debugPrint('[BackgroundTranscription] ❌ Error saving: $e');

      // Notify failure
      for (final listener in _completionListeners) {
        listener(false);
      }
    }
  }

  /// Add a listener for segment updates
  void addSegmentListener(Function(TranscriptionSegment) listener) {
    _segmentListeners.add(listener);
  }

  /// Remove a segment listener
  void removeSegmentListener(Function(TranscriptionSegment) listener) {
    _segmentListeners.remove(listener);
  }

  /// Add a listener for completion events
  void addCompletionListener(Function(bool) listener) {
    _completionListeners.add(listener);
  }

  /// Remove a completion listener
  void removeCompletionListener(Function(bool) listener) {
    _completionListeners.remove(listener);
  }

  /// Check if currently monitoring a transcription
  bool get isMonitoring => _activeService != null;

  /// Get the current timestamp being transcribed
  String? get currentTimestamp => _timestamp;

  /// Get all current segments
  List<TranscriptionSegment> get segments => _activeService?.segments ?? [];

  /// Get combined text from current transcription
  String get combinedText => _activeService?.getCombinedText() ?? '';

  /// Stop monitoring (but don't dispose service - it may still be in use)
  void stopMonitoring() {
    debugPrint('[BackgroundTranscription] Stopping monitoring');
    _subscription?.cancel();
    _subscription = null;
    _activeService = null;
    _timestamp = null;
    _duration = null;
    _capturesPath = null;
    _segmentListeners.clear();
    _completionListeners.clear();
  }

  void dispose() {
    stopMonitoring();
  }
}
