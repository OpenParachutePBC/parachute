import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:async';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Local-first storage service for recording management
///
/// All recordings are stored in ~/Parachute/captures/ as:
/// - Audio file (.opus for new recordings, .wav for legacy)
/// - Markdown transcript file (.md)
/// - JSON metadata file (.json)
class StorageService {
  final Ref? _ref; // Optional ref for accessing providers (like Git sync)

  static const String _hasInitializedKey = 'has_initialized';
  static const String _openaiApiKeyKey = 'openai_api_key';
  static const String _geminiApiKeyKey = 'gemini_api_key';
  static const String _transcriptionModeKey = 'transcription_mode';
  static const String _preferredWhisperModelKey = 'preferred_whisper_model';
  static const String _autoTranscribeKey = 'auto_transcribe';
  static const String _autoPauseRecordingKey = 'auto_pause_recording';
  static const String _audioDebugOverlayKey = 'audio_debug_overlay';
  static const String _titleGenerationModeKey = 'title_generation_mode';
  static const String _preferredGemmaModelKey = 'preferred_gemma_model';
  static const String _preferredSmolLMModelKey = 'preferred_smollm_model';
  static const String _preferredOllamaModelKey = 'preferred_ollama_model';
  static const String _huggingfaceTokenKey = 'huggingface_token';

  final FileSystemService _fileSystem = FileSystemService();
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  // Cache for recordings to avoid excessive disk reads
  List<Recording>? _cachedRecordings;
  DateTime? _cacheTimestamp;
  // Increased cache duration - filesystem reads are expensive
  // Cache is invalidated explicitly when app makes changes
  static const Duration _cacheDuration = Duration(seconds: 30);

  // Filesystem watcher removed - it was causing excessive refreshes
  // The app now relies on explicit cache invalidation when it makes changes
  // External changes (git pull, Obsidian) will be picked up on next app open
  // or when user does pull-to-refresh

  StorageService([this._ref]);

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Wait for initialization to complete.
  /// Safe to call multiple times - will return immediately if already initialized.
  Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    await initialize();
  }

  /// Invalidate the recordings cache
  void _invalidateCache() {
    _cachedRecordings = null;
    _cacheTimestamp = null;
  }

  /// Force refresh recordings from filesystem (bypasses cache)
  void forceRefresh() {
    debugPrint('[StorageService] Force refresh requested, invalidating cache');
    _invalidateCache();
  }

  /// @deprecated Filesystem watcher has been removed due to performance issues.
  /// The app now relies on explicit cache invalidation and pull-to-refresh.
  /// This method is kept for backwards compatibility but does nothing.
  Future<void> startWatchingFilesystem({void Function()? onChange}) async {
    // No-op: Filesystem watcher removed to prevent excessive refreshes
    debugPrint(
      '[StorageService] Filesystem watcher disabled (performance optimization)',
    );
  }

  /// @deprecated Filesystem watcher has been removed.
  Future<void> stopWatchingFilesystem() async {
    // No-op
  }

  /// @deprecated Filesystem watcher has been removed.
  void setIgnoredRecordingPath(String? path) {
    // No-op
  }

  /// @deprecated Filesystem watcher has been removed.
  void clearIgnoredRecordingPath() {
    // No-op
  }

  /// Initialize the storage service and ensure sync folder is set up
  Future<void> initialize() async {
    // If already initialized, return immediately
    if (_isInitialized) return;

    // If initialization is in progress, wait for it to complete
    if (_initializationFuture != null) {
      return _initializationFuture;
    }

    // Start initialization and store the future
    _initializationFuture = _doInitialize();
    await _initializationFuture;
  }

  Future<void> _doInitialize() async {
    try {
      debugPrint('[StorageService] Starting initialization...');

      // Initialize the file system service
      await _fileSystem.initialize();
      debugPrint('[StorageService] FileSystemService initialized');

      final prefs = await SharedPreferences.getInstance();

      // Create sample recordings on first launch
      final hasInitialized = prefs.getBool(_hasInitializedKey) ?? false;
      debugPrint('StorageService: Has initialized: $hasInitialized');
      if (!hasInitialized) {
        debugPrint('StorageService: Creating sample recordings...');
        await _createSampleRecordings();
        await prefs.setBool(_hasInitializedKey, true);
      }

      _isInitialized = true;
      _initializationFuture = null;
      debugPrint('[StorageService] Initialization complete');
    } catch (e, stackTrace) {
      debugPrint('[StorageService] Error during initialization: $e');
      debugPrint('[StorageService] Stack trace: $stackTrace');
      _initializationFuture = null;
      rethrow;
    }
  }

  /// Get the current captures folder path (replaces getSyncFolderPath)
  Future<String> getSyncFolderPath() async {
    await initialize();
    return await _fileSystem.getCapturesPath();
  }

  /// Set a new root folder path (for user configuration)
  Future<bool> setSyncFolderPath(String path) async {
    try {
      return await _fileSystem.setRootPath(path);
    } catch (e) {
      debugPrint('[StorageService] Error setting root path: $e');
      return false;
    }
  }

  /// Get the path for a recording's audio file
  Future<String> _getAudioPath(String recordingId, DateTime timestamp) async {
    final capturesPath = await _fileSystem.getCapturesPath();
    final timestampStr = FileSystemService.formatTimestampForFilename(
      timestamp,
    );
    return '$capturesPath/$timestampStr.opus';
  }

  /// Load all recordings from local filesystem (LOCAL-FIRST)
  ///
  /// If [includeOrphaned] is true, also includes WAV files without markdown
  Future<List<Recording>> getRecordings({bool includeOrphaned = false}) async {
    await initialize();

    // Check if cache is valid
    if (_cachedRecordings != null && _cacheTimestamp != null) {
      final cacheAge = DateTime.now().difference(_cacheTimestamp!);
      if (cacheAge < _cacheDuration) {
        debugPrint(
          '[StorageService] Using cached recordings (${_cachedRecordings!.length} items, age: ${cacheAge.inMilliseconds}ms)',
        );
        return _cachedRecordings!;
      }
    }

    try {
      debugPrint(
        '[StorageService] Loading recordings from local filesystem...',
      );
      final capturesPath = await _fileSystem.getCapturesPath();
      final capturesDir = Directory(capturesPath);

      if (!await capturesDir.exists()) {
        debugPrint('[StorageService] Captures directory does not exist yet');
        return [];
      }

      // Find all markdown files (each represents a recording)
      final recordings = <Recording>[];
      final processedIds = <String>{};

      await for (final entity in capturesDir.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          try {
            final recording = await _loadRecordingFromMarkdown(entity);
            if (recording != null) {
              recordings.add(recording);
              processedIds.add(recording.id);
            }
          } catch (e) {
            debugPrint(
              '[StorageService] Error loading recording from ${entity.path}: $e',
            );
          }
        }
      }

      // If requested, also load orphaned audio files (WAV or Opus)
      if (includeOrphaned) {
        await for (final entity in capturesDir.list()) {
          if (entity is File &&
              (entity.path.endsWith('.wav') || entity.path.endsWith('.opus'))) {
            final filename = p.basename(entity.path);
            final id = filename.replaceAll('.wav', '').replaceAll('.opus', '');

            // Skip if we already have a markdown file for this recording
            if (processedIds.contains(id)) continue;

            try {
              final orphanedRecording = await _loadOrphanedAudioFile(entity);
              if (orphanedRecording != null) {
                recordings.add(orphanedRecording);
              }
            } catch (e) {
              debugPrint(
                '[StorageService] Error loading orphaned audio from ${entity.path}: $e',
              );
            }
          }
        }
      }

      // Sort by timestamp (newest first)
      recordings.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Update cache
      _cachedRecordings = recordings;
      _cacheTimestamp = DateTime.now();

      debugPrint(
        '[StorageService] Loaded ${recordings.length} recordings from filesystem',
      );
      return recordings;
    } catch (e) {
      debugPrint('[StorageService] Error loading recordings: $e');
      return [];
    }
  }

  /// Load an orphaned audio file (one without a corresponding markdown file)
  Future<Recording?> _loadOrphanedAudioFile(File audioFile) async {
    try {
      final filename = p.basename(audioFile.path);

      // Extract timestamp from filename
      final timestamp = FileSystemService.parseTimestampFromFilename(filename);
      if (timestamp == null) {
        debugPrint(
          '[StorageService] Could not parse timestamp from: $filename',
        );
        return null;
      }

      // Get file stats
      final stat = await audioFile.stat();
      final fileSizeKB = stat.size / 1024;

      // Try to get audio duration using just_audio
      Duration duration = Duration.zero;
      try {
        // Create a temporary AudioPlayer to read duration
        final player = AudioPlayer();
        await player.setFilePath(audioFile.path);
        duration = player.duration ?? Duration.zero;
        await player.dispose();
        debugPrint(
          '[StorageService] Got duration for orphaned file: ${duration.inSeconds}s',
        );
      } catch (e) {
        debugPrint(
          '[StorageService] Could not get duration for orphaned file: $e',
        );
        // Continue with zero duration
      }

      // Create a recording object with placeholder data
      return Recording(
        id: filename.replaceAll('.wav', '').replaceAll('.opus', ''),
        title: 'Untranscribed Recording',
        filePath: audioFile.path,
        timestamp: timestamp,
        duration: duration,
        tags: [],
        transcript: '',
        context: '',
        fileSizeKB: fileSizeKB,
        source: RecordingSource.phone,
        transcriptionStatus: ProcessingStatus
            .failed, // Mark as failed since no transcript exists
      );
    } catch (e) {
      debugPrint('[StorageService] Error loading orphaned audio file: $e');
      return null;
    }
  }

  /// Load a recording from a markdown file
  Future<Recording?> _loadRecordingFromMarkdown(File mdFile) async {
    try {
      final content = await mdFile.readAsString();
      final filename = p.basename(mdFile.path);

      // Extract timestamp from filename (e.g., "2025-11-05_14-30-22.md")
      final timestamp = FileSystemService.parseTimestampFromFilename(filename);
      if (timestamp == null) {
        debugPrint(
          '[StorageService] Could not parse timestamp from: $filename',
        );
        return null;
      }

      // Parse YAML frontmatter
      String? durationStr;
      String? source;
      String? title;
      String? liveTranscriptionStatusStr;
      String? contextFromFrontmatter;
      String? summaryFromFrontmatter;
      List<RecordingSegment>? segments;

      final lines = content.split('\n');
      if (lines.isNotEmpty && lines[0] == '---') {
        // Find end of frontmatter
        int endIndex = -1;
        for (int i = 1; i < lines.length; i++) {
          if (lines[i] == '---') {
            endIndex = i;
            break;
          }
        }

        if (endIndex > 0) {
          // Parse frontmatter fields
          bool inSegments = false;
          double? currentSegmentEnd;
          DateTime? currentSegmentRecorded;

          for (int i = 1; i < endIndex; i++) {
            final line = lines[i];

            // Check for segment list items
            if (inSegments) {
              if (line.startsWith('  - end:')) {
                // Save previous segment if exists
                if (currentSegmentEnd != null &&
                    currentSegmentRecorded != null) {
                  segments ??= [];
                  segments.add(RecordingSegment(
                    endSeconds: currentSegmentEnd,
                    recorded: currentSegmentRecorded,
                  ));
                }
                // Start new segment
                final endValue = line.substring('  - end:'.length).trim();
                currentSegmentEnd = double.tryParse(endValue);
                currentSegmentRecorded = null;
              } else if (line.startsWith('    recorded:')) {
                final recordedValue =
                    line.substring('    recorded:'.length).trim();
                currentSegmentRecorded = DateTime.tryParse(recordedValue);
              } else if (!line.startsWith('  ')) {
                // End of segments section - save last segment
                if (currentSegmentEnd != null &&
                    currentSegmentRecorded != null) {
                  segments ??= [];
                  segments.add(RecordingSegment(
                    endSeconds: currentSegmentEnd,
                    recorded: currentSegmentRecorded,
                  ));
                }
                inSegments = false;
                currentSegmentEnd = null;
                currentSegmentRecorded = null;
              }
            }

            if (line.contains(':') && !inSegments) {
              final parts = line.split(':');
              final key = parts[0].trim();
              final value = parts.sublist(1).join(':').trim();

              if (key == 'duration') durationStr = value;
              if (key == 'source') source = value;
              if (key == 'title') title = value;
              if (key == 'transcription_status') {
                liveTranscriptionStatusStr = value;
              }
              if (key == 'segments') {
                inSegments = true;
              }
              if (key == 'context') {
                // Unescape the context value (remove quotes and unescape)
                String unescapedContext = value;
                if (unescapedContext.startsWith('"') &&
                    unescapedContext.endsWith('"')) {
                  unescapedContext = unescapedContext.substring(
                    1,
                    unescapedContext.length - 1,
                  );
                }
                unescapedContext = unescapedContext
                    .replaceAll('\\n', '\n')
                    .replaceAll('\\"', '"');
                contextFromFrontmatter = unescapedContext;
              }
              if (key == 'summary') {
                // Unescape the summary value (remove quotes and unescape)
                String unescapedSummary = value;
                if (unescapedSummary.startsWith('"') &&
                    unescapedSummary.endsWith('"')) {
                  unescapedSummary = unescapedSummary.substring(
                    1,
                    unescapedSummary.length - 1,
                  );
                }
                unescapedSummary = unescapedSummary
                    .replaceAll('\\n', '\n')
                    .replaceAll('\\"', '"');
                summaryFromFrontmatter = unescapedSummary;
              }
            }
          }

          // Save last segment if we ended while still in segments section
          if (inSegments &&
              currentSegmentEnd != null &&
              currentSegmentRecorded != null) {
            segments ??= [];
            segments.add(RecordingSegment(
              endSeconds: currentSegmentEnd,
              recorded: currentSegmentRecorded,
            ));
          }
        }
      }

      // Extract transcript (skip frontmatter)
      String transcript = '';

      // Context and summary come from frontmatter now
      String context = contextFromFrontmatter ?? '';
      String summary = summaryFromFrontmatter ?? '';

      if (lines.isNotEmpty && lines[0] == '---') {
        final endIndex = lines.indexOf('---', 1);
        if (endIndex > 0 && endIndex + 1 < lines.length) {
          final bodyLines = lines.sublist(endIndex + 1);

          // Skip empty lines at the beginning
          int i = 0;
          while (i < bodyLines.length && bodyLines[i].trim().isEmpty) {
            i++;
          }

          // Rest is transcript (no more sections)
          if (i < bodyLines.length) {
            transcript = bodyLines.sublist(i).join('\n').trim();
          }
        }
      }

      // Parse duration (stored as seconds in frontmatter)
      Duration duration = Duration.zero;
      if (durationStr != null) {
        // Try parsing as seconds (new format)
        final seconds = int.tryParse(durationStr);
        if (seconds != null) {
          duration = Duration(seconds: seconds);
        } else {
          // Fallback: try parsing as "MM:SS" (legacy format)
          final parts = durationStr.split(':');
          if (parts.length == 2) {
            final minutes = int.tryParse(parts[0]) ?? 0;
            final secs = int.tryParse(parts[1]) ?? 0;
            duration = Duration(minutes: minutes, seconds: secs);
          }
        }
      }

      // Check if corresponding audio file exists (try .opus first, then .wav)
      String? audioPath;
      bool audioExists = false;

      final opusPath = mdFile.path.replaceAll('.md', '.opus');
      if (await File(opusPath).exists()) {
        audioPath = opusPath;
        audioExists = true;
      } else {
        final wavPath = mdFile.path.replaceAll('.md', '.wav');
        if (await File(wavPath).exists()) {
          audioPath = wavPath;
          audioExists = true;
        }
      }

      // Use title from frontmatter, or extract from transcript as fallback
      final recordingTitle = title ?? _extractTitleFromTranscript(transcript);

      // Get file size
      final stat = await mdFile.stat();
      final fileSizeKB = stat.size / 1024;

      // Determine recording source
      final recordingSource = source == 'omiDevice'
          ? RecordingSource.omiDevice
          : RecordingSource.phone;

      // Determine transcriptionStatus based on liveTranscriptionStatus
      ProcessingStatus finalTranscriptionStatus;
      if (liveTranscriptionStatusStr == 'in_progress') {
        // Mark as processing if live transcription was in progress
        finalTranscriptionStatus = ProcessingStatus.processing;
      } else if (liveTranscriptionStatusStr == 'completed') {
        finalTranscriptionStatus = ProcessingStatus.completed;
      } else if (transcript.isEmpty) {
        // No transcript and no status = failed/pending
        finalTranscriptionStatus = ProcessingStatus.pending;
      } else {
        // Has transcript = completed
        finalTranscriptionStatus = ProcessingStatus.completed;
      }

      return Recording(
        id: filename.replaceAll('.md', ''), // Use timestamp as ID
        title: recordingTitle,
        filePath: audioExists ? audioPath! : mdFile.path,
        timestamp: timestamp,
        duration: duration,
        tags: [],
        transcript: transcript,
        context: context,
        summary: summary,
        fileSizeKB: fileSizeKB,
        source: recordingSource,
        deviceId: recordingSource == RecordingSource.omiDevice
            ? 'unknown'
            : null,
        buttonTapCount: null,
        transcriptionStatus: finalTranscriptionStatus,
        liveTranscriptionStatus: liveTranscriptionStatusStr,
        segments: segments,
      );
    } catch (e) {
      debugPrint('[StorageService] Error loading recording from markdown: $e');
      return null;
    }
  }

  /// Extract title from transcript (first line or first 50 chars)
  String _extractTitleFromTranscript(String transcript) {
    if (transcript.isEmpty) return 'Untitled';

    final firstLine = transcript.split('\n').first.trim();
    if (firstLine.length <= 50) return firstLine;

    return '${firstLine.substring(0, 47)}...';
  }

  /// Save a recording - LOCAL-FIRST
  /// Returns the recording ID (timestamp-based for local files)
  ///
  /// All recordings are saved to ~/Parachute/captures/ as .opus, .md, and .json files.
  /// Git sync handles multi-device synchronization.
  Future<String?> saveRecording(Recording recording) async {
    if (!_isInitialized && _initializationFuture == null) {
      await initialize();
    }

    try {
      // Check if audio file exists locally
      final audioFile = File(recording.filePath);
      if (!await audioFile.exists()) {
        debugPrint(
          '[StorageService] Audio file not found: ${recording.filePath}',
        );
        return null;
      }

      // Ensure the recording is saved to captures folder
      final capturesPath = await _fileSystem.getCapturesPath();
      final timestamp = FileSystemService.formatTimestampForFilename(
        recording.timestamp,
      );

      // Save markdown file with transcript
      final mdPath = p.join(capturesPath, '$timestamp.md');
      final mdFile = File(mdPath);

      if (!await mdFile.exists()) {
        final markdown = _generateMarkdown(recording);
        await mdFile.writeAsString(markdown);
        debugPrint('[StorageService] Saved recording locally: $mdPath');
      }

      // Copy audio file if not already in captures folder
      // Preserve the original extension (.opus or .wav)
      final audioExtension = p.extension(recording.filePath);
      final audioDestPath = p.join(capturesPath, '$timestamp$audioExtension');
      if (recording.filePath != audioDestPath &&
          !await File(audioDestPath).exists()) {
        await audioFile.copy(audioDestPath);
        debugPrint('[StorageService] Copied audio to: $audioDestPath');
      }

      debugPrint('[StorageService] ✅ Recording saved locally');

      // Invalidate cache since we added a new recording
      _invalidateCache();

      return timestamp; // Return timestamp as ID for local-first architecture
    } catch (e) {
      debugPrint('[StorageService] Error saving recording locally: $e');
      return null;
    }
  }

  /// Generate markdown content from recording
  String _generateMarkdown(Recording recording) {
    final buffer = StringBuffer();

    // Frontmatter
    buffer.writeln('---');
    buffer.writeln('id: ${recording.id}');
    buffer.writeln('title: ${recording.title}');
    buffer.writeln('created: ${recording.timestamp.toIso8601String()}');
    buffer.writeln('duration: ${recording.duration.inSeconds}');
    buffer.writeln('fileSize: ${recording.fileSizeKB}');
    buffer.writeln('source: ${recording.source}');

    if (recording.deviceId != null) {
      buffer.writeln('deviceId: ${recording.deviceId}');
    }

    if (recording.buttonTapCount != null) {
      buffer.writeln('buttonTapCount: ${recording.buttonTapCount}');
    }

    // Context in frontmatter (if provided)
    if (recording.context.isNotEmpty) {
      // Escape quotes and newlines for YAML
      final escapedContext = recording.context
          .replaceAll('"', '\\"')
          .replaceAll('\n', '\\n');
      buffer.writeln('context: "$escapedContext"');
    }

    // Summary in frontmatter (if provided)
    if (recording.summary.isNotEmpty) {
      // Escape quotes and newlines for YAML
      final escapedSummary = recording.summary
          .replaceAll('"', '\\"')
          .replaceAll('\n', '\\n');
      buffer.writeln('summary: "$escapedSummary"');
    }

    if (recording.tags.isNotEmpty) {
      buffer.writeln('tags:');
      for (final tag in recording.tags) {
        buffer.writeln('  - $tag');
      }
    }

    if (recording.liveTranscriptionStatus != null) {
      buffer.writeln(
        'transcription_status: ${recording.liveTranscriptionStatus}',
      );
    }

    // Segments for recordings with multiple appended parts
    if (recording.segments != null && recording.segments!.isNotEmpty) {
      buffer.writeln('segments:');
      for (final segment in recording.segments!) {
        buffer.writeln('  - end: ${segment.endSeconds}');
        buffer.writeln('    recorded: ${segment.recorded.toIso8601String()}');
      }
    }

    buffer.writeln('---');
    buffer.writeln();

    // Content - just the transcript (no sections)
    if (recording.transcript.isNotEmpty) {
      buffer.writeln(recording.transcript);
    }

    return buffer.toString();
  }

  /// Update an existing recording (LOCAL-FIRST)
  /// Updates the markdown file with new title, transcript, and context
  Future<bool> updateRecording(Recording updatedRecording) async {
    try {
      debugPrint(
        '[StorageService] 📝 Updating recording: ${updatedRecording.id}',
      );

      // Get the captures folder path
      final capturesPath = await _fileSystem.getCapturesPath();

      // The recordingId is the timestamp (e.g., "2025-11-06_12-30-45")
      final mdPath = p.join(capturesPath, '${updatedRecording.id}.md');
      final mdFile = File(mdPath);

      if (!await mdFile.exists()) {
        debugPrint(
          '[StorageService] ℹ️ Markdown file not found, creating new one for orphaned recording: $mdPath',
        );
        // For orphaned recordings, create the markdown file
        // This allows transcription results to be saved
      }

      // Generate updated markdown content
      final markdown = _generateMarkdown(updatedRecording);

      // Write updated content to file (creates if doesn't exist)
      await mdFile.writeAsString(markdown);
      debugPrint('[StorageService] ✅ Updated markdown file: $mdPath');

      // Invalidate cache since we modified a recording
      _invalidateCache();

      return true;
    } catch (e, stackTrace) {
      debugPrint('[StorageService] ❌ Error updating recording: $e');
      debugPrint('[StorageService] Stack trace: $stackTrace');
      return false;
    }
  }

  /// Append a new segment to an existing recording
  ///
  /// This updates the recording with:
  /// - Appended transcript text
  /// - Updated duration
  /// - New segment metadata
  /// - Updated file size
  ///
  /// Note: Audio file appending should be done separately using AudioService.appendWavFile
  Future<bool> appendToRecording({
    required String recordingId,
    required String newTranscript,
    required double newSegmentEndSeconds,
    required DateTime segmentRecordedAt,
    required double newFileSizeKB,
  }) async {
    try {
      debugPrint(
        '[StorageService] 📎 Appending to recording: $recordingId',
      );

      // Load existing recording
      final existing = await getRecording(recordingId);
      if (existing == null) {
        debugPrint('[StorageService] ❌ Recording not found: $recordingId');
        return false;
      }

      // Build updated segments list
      List<RecordingSegment> updatedSegments;
      if (existing.segments != null && existing.segments!.isNotEmpty) {
        // Add new segment to existing list
        updatedSegments = [
          ...existing.segments!,
          RecordingSegment(
            endSeconds: newSegmentEndSeconds,
            recorded: segmentRecordedAt,
          ),
        ];
      } else {
        // First append - create initial segment for original recording
        // and add the new segment
        final originalDurationSeconds = existing.duration.inMilliseconds / 1000;
        updatedSegments = [
          RecordingSegment(
            endSeconds: originalDurationSeconds,
            recorded: existing.timestamp,
          ),
          RecordingSegment(
            endSeconds: newSegmentEndSeconds,
            recorded: segmentRecordedAt,
          ),
        ];
      }

      // Append transcript with separator
      final updatedTranscript = existing.transcript.isEmpty
          ? newTranscript
          : '${existing.transcript}\n\n$newTranscript';

      // Calculate new duration from final segment end
      final newDuration = Duration(
        milliseconds: (newSegmentEndSeconds * 1000).round(),
      );

      // Create updated recording
      final updated = existing.copyWith(
        transcript: updatedTranscript,
        duration: newDuration,
        segments: updatedSegments,
        fileSizeKB: newFileSizeKB,
      );

      // Save the updated recording
      return await updateRecording(updated);
    } catch (e, stackTrace) {
      debugPrint('[StorageService] ❌ Error appending to recording: $e');
      debugPrint('[StorageService] Stack trace: $stackTrace');
      return false;
    }
  }

  /// Delete a recording from local filesystem (LOCAL-FIRST)
  Future<bool> deleteRecording(String recordingId) async {
    try {
      debugPrint('[StorageService] 🗑️  Deleting recording: $recordingId');

      // Get the captures folder path
      final capturesPath = await _fileSystem.getCapturesPath();

      // The recordingId is the timestamp (e.g., "2025-11-06_12-30-45")
      // We need to delete audio (.opus or .wav), .md, and .json files
      final basePath = p.join(capturesPath, recordingId);
      final opusPath = '$basePath.opus';
      final wavPath = '$basePath.wav';
      final mdPath = '$basePath.md';
      final jsonPath = '$basePath.json';

      int deletedCount = 0;

      // Delete .opus file if exists
      final opusFile = File(opusPath);
      if (await opusFile.exists()) {
        await opusFile.delete();
        debugPrint('[StorageService] ✅ Deleted audio file: $opusPath');
        deletedCount++;
      }

      // Delete .wav file if exists (legacy)
      final wavFile = File(wavPath);
      if (await wavFile.exists()) {
        await wavFile.delete();
        debugPrint('[StorageService] ✅ Deleted audio file: $wavPath');
        deletedCount++;
      }

      // Delete .md file if exists
      final mdFile = File(mdPath);
      if (await mdFile.exists()) {
        await mdFile.delete();
        debugPrint('[StorageService] ✅ Deleted markdown file: $mdPath');
        deletedCount++;
      }

      // Delete .json file if exists
      final jsonFile = File(jsonPath);
      if (await jsonFile.exists()) {
        await jsonFile.delete();
        debugPrint('[StorageService] ✅ Deleted JSON file: $jsonPath');
        deletedCount++;
      }

      if (deletedCount > 0) {
        debugPrint(
          '[StorageService] ✅ Deleted $deletedCount file(s) for recording: $recordingId',
        );

        // Invalidate cache since we deleted a recording
        _invalidateCache();

        return true;
      } else {
        debugPrint(
          '[StorageService] ⚠️  No files found to delete for: $recordingId',
        );
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('[StorageService] ❌ Error deleting recording: $e');
      debugPrint('[StorageService] Stack trace: $stackTrace');
      return false;
    }
  }

  /// Get a single recording by ID
  Future<Recording?> getRecording(String recordingId) async {
    debugPrint('[StorageService] Looking for recording with ID: $recordingId');
    final recordings = await getRecordings();
    try {
      final found = recordings.firstWhere((r) => r.id == recordingId);
      debugPrint('[StorageService] Found recording: ${found.id}');
      return found;
    } catch (e) {
      debugPrint(
        '[StorageService] Recording not found in list of ${recordings.length} recordings',
      );
      debugPrint(
        '[StorageService] Available IDs: ${recordings.map((r) => r.id).take(5).join(", ")}...',
      );
      return null;
    }
  }

  /// Create sample recordings for demo purposes
  Future<void> _createSampleRecordings() async {
    final now = DateTime.now();

    final timestamp1 = now.subtract(const Duration(hours: 2));
    final timestamp2 = now.subtract(const Duration(days: 1));
    final timestamp3 = now.subtract(const Duration(hours: 5));

    final sampleRecordings = [
      Recording(
        id: 'sample_1',
        title: 'Welcome to Parachute',
        filePath: await _getAudioPath('sample_1', timestamp1),
        timestamp: timestamp1,
        duration: const Duration(minutes: 1, seconds: 30),
        tags: ['welcome', 'tutorial'],
        transcript:
            'Welcome to Parachute, your personal voice recording assistant. '
            'This app helps you capture thoughts, ideas, and important moments with ease.',
        fileSizeKB: 450,
      ),
      Recording(
        id: 'sample_2',
        title: 'Meeting Notes',
        filePath: await _getAudioPath('sample_2', timestamp2),
        timestamp: timestamp2,
        duration: const Duration(minutes: 15, seconds: 45),
        tags: ['work', 'meeting', 'project-alpha'],
        transcript:
            'Today we discussed the new features for Project Alpha. '
            'Key decisions: 1) Move deadline to next quarter, 2) Add two more developers to the team, '
            '3) Focus on mobile-first approach.',
        fileSizeKB: 2340,
      ),
      Recording(
        id: 'sample_3',
        title: 'Quick Reminder',
        filePath: await _getAudioPath('sample_3', timestamp3),
        timestamp: timestamp3,
        duration: const Duration(seconds: 45),
        tags: ['personal', 'reminder'],
        transcript:
            'Remember to call the dentist tomorrow morning to schedule the appointment. '
            'Also, pick up groceries on the way home.',
        fileSizeKB: 180,
      ),
    ];

    for (final recording in sampleRecordings) {
      await saveRecording(recording);

      // Create empty placeholder audio files
      final audioFile = File(recording.filePath);
      if (!await audioFile.exists()) {
        await audioFile.create(recursive: true);
      }
    }
  }

  /// Clear all recordings
  Future<void> clearAllRecordings() async {
    final recordings = await getRecordings();
    for (final recording in recordings) {
      await deleteRecording(recording.id);
    }
  }

  // OpenAI API Key Management (kept in SharedPreferences as it's config, not data)
  Future<String?> getOpenAIApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_openaiApiKeyKey);
    } catch (e) {
      debugPrint('Error getting OpenAI API key: $e');
      return null;
    }
  }

  Future<bool> saveOpenAIApiKey(String apiKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_openaiApiKeyKey, apiKey.trim());
    } catch (e) {
      debugPrint('Error saving OpenAI API key: $e');
      return false;
    }
  }

  Future<bool> deleteOpenAIApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_openaiApiKeyKey);
    } catch (e) {
      debugPrint('Error deleting OpenAI API key: $e');
      return false;
    }
  }

  Future<bool> hasOpenAIApiKey() async {
    final apiKey = await getOpenAIApiKey();
    return apiKey != null && apiKey.isNotEmpty;
  }

  // Gemini API Key Management
  Future<String?> getGeminiApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_geminiApiKeyKey);
    } catch (e) {
      debugPrint('Error getting Gemini API key: $e');
      return null;
    }
  }

  Future<bool> saveGeminiApiKey(String apiKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_geminiApiKeyKey, apiKey.trim());
    } catch (e) {
      debugPrint('Error saving Gemini API key: $e');
      return false;
    }
  }

  Future<bool> deleteGeminiApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_geminiApiKeyKey);
    } catch (e) {
      debugPrint('Error deleting Gemini API key: $e');
      return false;
    }
  }

  Future<bool> hasGeminiApiKey() async {
    final apiKey = await getGeminiApiKey();
    return apiKey != null && apiKey.isNotEmpty;
  }

  // Local Whisper Configuration

  /// Get transcription mode (api or local)
  Future<String> getTranscriptionMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_transcriptionModeKey) ?? 'api';
    } catch (e) {
      debugPrint('Error getting transcription mode: $e');
      return 'api';
    }
  }

  /// Set transcription mode
  Future<bool> setTranscriptionMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_transcriptionModeKey, mode);
    } catch (e) {
      debugPrint('Error setting transcription mode: $e');
      return false;
    }
  }

  /// Get preferred Whisper model
  Future<String?> getPreferredWhisperModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_preferredWhisperModelKey);
    } catch (e) {
      debugPrint('Error getting preferred Whisper model: $e');
      return null;
    }
  }

  /// Set preferred Whisper model
  Future<bool> setPreferredWhisperModel(String modelName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_preferredWhisperModelKey, modelName);
    } catch (e) {
      debugPrint('Error setting preferred Whisper model: $e');
      return false;
    }
  }

  /// Get auto-transcribe setting
  Future<bool> getAutoTranscribe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_autoTranscribeKey) ?? false;
    } catch (e) {
      debugPrint('Error getting auto-transcribe setting: $e');
      return false;
    }
  }

  /// Set auto-transcribe setting
  Future<bool> setAutoTranscribe(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(_autoTranscribeKey, enabled);
    } catch (e) {
      debugPrint('Error setting auto-transcribe: $e');
      return false;
    }
  }

  /// Get auto-pause recording setting (VAD-based auto-chunking)
  Future<bool> getAutoPauseRecording() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_autoPauseRecordingKey) ?? true; // Default: ON
    } catch (e) {
      debugPrint('Error getting auto-pause recording setting: $e');
      return true; // Default: ON
    }
  }

  /// Set auto-pause recording setting
  Future<bool> setAutoPauseRecording(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(_autoPauseRecordingKey, enabled);
    } catch (e) {
      debugPrint('Error setting auto-pause recording: $e');
      return false;
    }
  }

  /// Get audio debug overlay setting
  Future<bool> getAudioDebugOverlay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_audioDebugOverlayKey) ?? true; // Default: ON
    } catch (e) {
      debugPrint('Error getting audio debug overlay: $e');
      return true;
    }
  }

  /// Set audio debug overlay setting
  Future<bool> setAudioDebugOverlay(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(_audioDebugOverlayKey, enabled);
    } catch (e) {
      debugPrint('Error setting audio debug overlay: $e');
      return false;
    }
  }

  // Title Generation Configuration

  /// Get title generation mode (api or local)
  Future<String> getTitleGenerationMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_titleGenerationModeKey) ?? 'api';
    } catch (e) {
      debugPrint('Error getting title generation mode: $e');
      return 'api';
    }
  }

  /// Set title generation mode
  Future<bool> setTitleGenerationMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_titleGenerationModeKey, mode);
    } catch (e) {
      debugPrint('Error setting title generation mode: $e');
      return false;
    }
  }

  /// Get preferred Gemma model
  Future<String?> getPreferredGemmaModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_preferredGemmaModelKey);
    } catch (e) {
      debugPrint('Error getting preferred Gemma model: $e');
      return null;
    }
  }

  /// Set preferred Gemma model
  Future<bool> setPreferredGemmaModel(String modelName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_preferredGemmaModelKey, modelName);
    } catch (e) {
      debugPrint('Error setting preferred Gemma model: $e');
      return false;
    }
  }

  // Ollama Configuration (for desktop platforms)

  /// Get preferred Ollama model
  Future<String?> getOllamaModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_preferredOllamaModelKey) ?? 'gemma2:2b';
    } catch (e) {
      debugPrint('Error getting preferred Ollama model: $e');
      return 'gemma2:2b'; // Default model
    }
  }

  /// Set preferred Ollama model
  Future<bool> setOllamaModel(String modelName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_preferredOllamaModelKey, modelName);
    } catch (e) {
      debugPrint('Error setting preferred Ollama model: $e');
      return false;
    }
  }

  // SmolLM Configuration

  /// Get preferred SmolLM model
  Future<String?> getPreferredSmolLMModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_preferredSmolLMModelKey);
    } catch (e) {
      debugPrint('Error getting preferred SmolLM model: $e');
      return null;
    }
  }

  /// Set preferred SmolLM model
  Future<bool> setPreferredSmolLMModel(String modelName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_preferredSmolLMModelKey, modelName);
    } catch (e) {
      debugPrint('Error setting preferred SmolLM model: $e');
      return false;
    }
  }

  // HuggingFace Token Management

  /// Get HuggingFace token for Gemma model downloads
  Future<String?> getHuggingFaceToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_huggingfaceTokenKey);
    } catch (e) {
      debugPrint('Error getting HuggingFace token: $e');
      return null;
    }
  }

  /// Save HuggingFace token
  Future<bool> saveHuggingFaceToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_huggingfaceTokenKey, token.trim());
    } catch (e) {
      debugPrint('Error saving HuggingFace token: $e');
      return false;
    }
  }

  /// Delete HuggingFace token
  Future<bool> deleteHuggingFaceToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_huggingfaceTokenKey);
    } catch (e) {
      debugPrint('Error deleting HuggingFace token: $e');
      return false;
    }
  }

  /// Check if HuggingFace token exists
  Future<bool> hasHuggingFaceToken() async {
    final token = await getHuggingFaceToken();
    return token != null && token.isNotEmpty;
  }

  // GitHub Token Management

  /// Get GitHub Access Token (expires after 8 hours when expiration is enabled)
  // TODO: Use secure storage when code signing is enabled
  // For now using SharedPreferences due to keychain entitlement requiring code signing
  Future<String?> getGitHubToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('github_token');
    } catch (e) {
      debugPrint('Error getting GitHub token: $e');
      return null;
    }
  }

  /// Save GitHub Access Token
  Future<bool> saveGitHubToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString('github_token', token);
    } catch (e) {
      debugPrint('Error saving GitHub token: $e');
      return false;
    }
  }

  /// Delete GitHub Access Token
  Future<bool> deleteGitHubToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('github_token');
      await prefs.remove('github_refresh_token');
      await prefs.remove('github_token_expires_at');
      await prefs.remove('github_refresh_token_expires_at');
      return true;
    } catch (e) {
      debugPrint('Error deleting GitHub token: $e');
      return false;
    }
  }

  /// Check if GitHub token exists
  Future<bool> hasGitHubToken() async {
    final token = await getGitHubToken();
    return token != null && token.isNotEmpty;
  }

  /// Get GitHub Refresh Token (used to obtain new access tokens)
  Future<String?> getGitHubRefreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('github_refresh_token');
    } catch (e) {
      debugPrint('Error getting GitHub refresh token: $e');
      return null;
    }
  }

  /// Save GitHub Refresh Token
  Future<bool> saveGitHubRefreshToken(String refreshToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString('github_refresh_token', refreshToken);
    } catch (e) {
      debugPrint('Error saving GitHub refresh token: $e');
      return false;
    }
  }

  /// Get GitHub Access Token expiration time
  Future<DateTime?> getGitHubTokenExpiresAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isoString = prefs.getString('github_token_expires_at');
      if (isoString != null) {
        return DateTime.parse(isoString);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting GitHub token expiration: $e');
      return null;
    }
  }

  /// Save GitHub Access Token expiration time
  Future<bool> saveGitHubTokenExpiresAt(DateTime expiresAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(
        'github_token_expires_at',
        expiresAt.toIso8601String(),
      );
    } catch (e) {
      debugPrint('Error saving GitHub token expiration: $e');
      return false;
    }
  }

  /// Get GitHub Refresh Token expiration time (6 months)
  Future<DateTime?> getGitHubRefreshTokenExpiresAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isoString = prefs.getString('github_refresh_token_expires_at');
      if (isoString != null) {
        return DateTime.parse(isoString);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting GitHub refresh token expiration: $e');
      return null;
    }
  }

  /// Save GitHub Refresh Token expiration time
  Future<bool> saveGitHubRefreshTokenExpiresAt(DateTime expiresAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(
        'github_refresh_token_expires_at',
        expiresAt.toIso8601String(),
      );
    } catch (e) {
      debugPrint('Error saving GitHub refresh token expiration: $e');
      return false;
    }
  }

  // GitHub Repository URL Management

  /// Get GitHub repository URL for Git sync
  Future<String?> getGitHubRepositoryUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('github_repository_url');
    } catch (e) {
      debugPrint('Error getting GitHub repository URL: $e');
      return null;
    }
  }

  /// Save GitHub repository URL
  Future<bool> saveGitHubRepositoryUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString('github_repository_url', url);
    } catch (e) {
      debugPrint('Error saving GitHub repository URL: $e');
      return false;
    }
  }

  /// Delete GitHub repository URL
  Future<bool> deleteGitHubRepositoryUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove('github_repository_url');
    } catch (e) {
      debugPrint('Error deleting GitHub repository URL: $e');
      return false;
    }
  }

  /// Check if Git sync is enabled
  Future<bool> isGitSyncEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('git_sync_enabled') ?? false;
    } catch (e) {
      debugPrint('Error checking Git sync enabled: $e');
      return false;
    }
  }

  /// Set Git sync enabled status
  Future<bool> setGitSyncEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool('git_sync_enabled', enabled);
    } catch (e) {
      debugPrint('Error setting Git sync enabled: $e');
      return false;
    }
  }
}
