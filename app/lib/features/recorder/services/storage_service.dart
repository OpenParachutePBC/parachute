import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/providers/git_sync_provider.dart';

/// Local-first storage service for recording management
///
/// All recordings are stored in ~/Parachute/captures/ as:
/// - Audio file (.wav)
/// - Markdown transcript file (.md)
/// - JSON metadata file (.json)
///
/// Git sync handles multi-device synchronization
class StorageService {
  final Ref? _ref; // Optional ref for accessing providers (like Git sync)
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

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
  static const String _huggingfaceTokenKey = 'huggingface_token';

  final FileSystemService _fileSystem = FileSystemService();
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  StorageService([this._ref]);

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
    return '$capturesPath/$timestampStr.wav';
  }

  /// Get the path for a recording's metadata markdown file (transcript)
  Future<String> _getMetadataPath(
    String recordingId,
    DateTime timestamp,
  ) async {
    final capturesPath = await _fileSystem.getCapturesPath();
    final timestampStr = FileSystemService.formatTimestampForFilename(
      timestamp,
    );
    return '$capturesPath/$timestampStr.md';
  }

  /// Get the path for a recording's JSON metadata file
  Future<String> _getJsonMetadataPath(
    String recordingId,
    DateTime timestamp,
  ) async {
    final capturesPath = await _fileSystem.getCapturesPath();
    final timestampStr = FileSystemService.formatTimestampForFilename(
      timestamp,
    );
    return '$capturesPath/$timestampStr.json';
  }

  /// Load all recordings from local filesystem (LOCAL-FIRST)
  Future<List<Recording>> getRecordings() async {
    await initialize();

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
      await for (final entity in capturesDir.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          try {
            final recording = await _loadRecordingFromMarkdown(entity);
            if (recording != null) {
              recordings.add(recording);
            }
          } catch (e) {
            debugPrint(
              '[StorageService] Error loading recording from ${entity.path}: $e',
            );
          }
        }
      }

      // Sort by timestamp (newest first)
      recordings.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      debugPrint(
        '[StorageService] Loaded ${recordings.length} recordings from filesystem',
      );
      return recordings;
    } catch (e) {
      debugPrint('[StorageService] Error loading recordings: $e');
      return [];
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
          for (int i = 1; i < endIndex; i++) {
            final line = lines[i];
            if (line.contains(':')) {
              final parts = line.split(':');
              final key = parts[0].trim();
              final value = parts.sublist(1).join(':').trim();

              if (key == 'duration') durationStr = value;
              if (key == 'source') source = value;
              if (key == 'title') title = value;
            }
          }
        }
      }

      // Extract transcript (skip frontmatter AND markdown headers)
      String transcript = '';
      String context = '';

      if (lines.isNotEmpty && lines[0] == '---') {
        final endIndex = lines.indexOf('---', 1);
        if (endIndex > 0 && endIndex + 1 < lines.length) {
          final bodyLines = lines.sublist(endIndex + 1);

          // Parse the body to extract context and transcript
          // Skip the title header (# Title)
          // Look for ## Context and ## Transcription sections
          int i = 0;

          // Skip empty lines and title header
          while (i < bodyLines.length) {
            final line = bodyLines[i].trim();
            if (line.isEmpty || line.startsWith('#')) {
              i++;
            } else {
              break;
            }
          }

          // Look for Context section
          if (i < bodyLines.length && bodyLines[i].trim() == '## Context') {
            i++; // Skip header
            while (i < bodyLines.length && bodyLines[i].trim().isEmpty)
              i++; // Skip empty lines

            final contextLines = <String>[];
            while (i < bodyLines.length &&
                !bodyLines[i].trim().startsWith('##')) {
              contextLines.add(bodyLines[i]);
              i++;
            }
            context = contextLines.join('\n').trim();
          }

          // Look for Transcription section
          if (i < bodyLines.length &&
              bodyLines[i].trim() == '## Transcription') {
            i++; // Skip header
            while (i < bodyLines.length && bodyLines[i].trim().isEmpty)
              i++; // Skip empty lines

            // Rest is transcript
            if (i < bodyLines.length) {
              transcript = bodyLines.sublist(i).join('\n').trim();
            }
          } else if (i < bodyLines.length) {
            // If no Transcription header, treat remaining content as transcript
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

      // Check if corresponding audio file exists
      final audioPath = mdFile.path.replaceAll('.md', '.wav');
      final audioExists = await File(audioPath).exists();

      // Use title from frontmatter, or extract from transcript as fallback
      final recordingTitle = title ?? _extractTitleFromTranscript(transcript);

      // Get file size
      final stat = await mdFile.stat();
      final fileSizeKB = stat.size / 1024;

      // Determine recording source
      final recordingSource = source == 'omiDevice'
          ? RecordingSource.omiDevice
          : RecordingSource.phone;

      return Recording(
        id: filename.replaceAll('.md', ''), // Use timestamp as ID
        title: recordingTitle,
        filePath: audioExists ? audioPath : mdFile.path,
        timestamp: timestamp,
        duration: duration,
        tags: [],
        transcript: transcript,
        context: context,
        fileSizeKB: fileSizeKB,
        source: recordingSource,
        deviceId: recordingSource == RecordingSource.omiDevice
            ? 'unknown'
            : null,
        buttonTapCount: null,
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
  /// All recordings are saved to ~/Parachute/captures/ as .wav, .md, and .json files.
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
      final audioDestPath = p.join(capturesPath, '$timestamp.wav');
      if (recording.filePath != audioDestPath &&
          !await File(audioDestPath).exists()) {
        await audioFile.copy(audioDestPath);
        debugPrint('[StorageService] Copied audio to: $audioDestPath');
      }

      debugPrint('[StorageService] ✅ Recording saved locally');

      // Trigger Git sync if enabled (async, don't wait for it)
      debugPrint('[StorageService] 🔄 Attempting to trigger auto-sync...');
      _triggerAutoSync();

      return timestamp; // Return timestamp as ID for local-first architecture
    } catch (e) {
      debugPrint('[StorageService] Error saving recording locally: $e');
      return null;
    }
  }

  /// Trigger Git sync in the background (don't block UI)
  void _triggerAutoSync() {
    debugPrint('[StorageService] 🔍 _triggerAutoSync called');

    if (_ref == null) {
      debugPrint('[StorageService] ❌ No ref available for auto-sync');
      return;
    }

    debugPrint('[StorageService] ✅ Ref is available, scheduling sync...');

    // Use Future.delayed with zero duration instead of microtask
    // This ensures state updates are properly propagated to listeners
    Future.delayed(Duration.zero, () async {
      try {
        debugPrint(
          '[StorageService] 📡 Inside Future.delayed, reading git sync state...',
        );

        final gitSync = _ref!.read(gitSyncProvider.notifier);
        final gitSyncState = _ref!.read(gitSyncProvider);

        debugPrint('[StorageService] Git sync state:');
        debugPrint('  - isEnabled: ${gitSyncState.isEnabled}');
        debugPrint('  - isSyncing: ${gitSyncState.isSyncing}');
        debugPrint('  - hasRemote: ${gitSyncState.hasRemote}');
        debugPrint('  - repositoryUrl: ${gitSyncState.repositoryUrl}');

        if (!gitSyncState.isEnabled) {
          debugPrint(
            '[StorageService] ⚠️  Git sync is NOT enabled, skipping auto-sync',
          );
          return;
        }

        if (gitSyncState.isSyncing) {
          debugPrint(
            '[StorageService] ⚠️  Git sync already in progress, skipping',
          );
          return;
        }

        debugPrint(
          '[StorageService] 🚀 Triggering auto-sync after recording save',
        );
        final success = await gitSync.sync();

        if (success) {
          debugPrint('[StorageService] ✅ Auto-sync completed successfully');
        } else {
          debugPrint('[StorageService] ❌ Auto-sync failed');
        }
      } catch (e, stackTrace) {
        debugPrint('[StorageService] ❌ Auto-sync error: $e');
        debugPrint('[StorageService] Stack trace: $stackTrace');
      }
    });
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

    if (recording.tags.isNotEmpty) {
      buffer.writeln('tags:');
      for (final tag in recording.tags) {
        buffer.writeln('  - $tag');
      }
    }

    buffer.writeln('---');
    buffer.writeln();

    // Content
    buffer.writeln('# ${recording.title}');
    buffer.writeln();

    // Context field (if provided)
    if (recording.context.isNotEmpty) {
      buffer.writeln('## Context');
      buffer.writeln();
      buffer.writeln(recording.context);
      buffer.writeln();
    }

    // Transcription
    if (recording.transcript.isNotEmpty) {
      buffer.writeln('## Transcription');
      buffer.writeln();
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
        debugPrint('[StorageService] ❌ Markdown file not found: $mdPath');
        return false;
      }

      // Generate updated markdown content
      final markdown = _generateMarkdown(updatedRecording);

      // Write updated content to file
      await mdFile.writeAsString(markdown);
      debugPrint('[StorageService] ✅ Updated markdown file: $mdPath');

      // Trigger Git sync to commit the update
      debugPrint('[StorageService] 🔄 Triggering auto-sync after update...');
      _triggerAutoSync();

      return true;
    } catch (e, stackTrace) {
      debugPrint('[StorageService] ❌ Error updating recording: $e');
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
      // We need to delete both .wav and .md files
      final basePath = p.join(capturesPath, recordingId);
      final wavPath = '$basePath.wav';
      final mdPath = '$basePath.md';
      final jsonPath = '$basePath.json';

      int deletedCount = 0;

      // Delete .wav file if exists
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

        // Trigger Git sync to commit the deletion
        debugPrint(
          '[StorageService] 🔄 Triggering auto-sync after deletion...',
        );
        _triggerAutoSync();

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

  /// Get GitHub Personal Access Token for Git sync
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

  /// Save GitHub Personal Access Token
  Future<bool> saveGitHubToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString('github_token', token);
    } catch (e) {
      debugPrint('Error saving GitHub token: $e');
      return false;
    }
  }

  /// Delete GitHub Personal Access Token
  Future<bool> deleteGitHubToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove('github_token');
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
