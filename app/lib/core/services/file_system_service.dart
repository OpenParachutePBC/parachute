import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';

/// Unified file system service for Parachute
///
/// Manages the ~/Parachute/ folder structure:
/// - Daily/          - Daily journal entries (YYYY-MM-DD.md)
/// - assets/         - All media files (audio, images) organized by YYYY-MM
/// - agent-sessions/ - AI chat sessions
/// - contexts/       - User context files for AI
/// - imports/        - Imported chat history (Claude, ChatGPT)
///
/// Legacy (read-only, no longer created):
/// - captures/       - Old voice recording transcripts
///
/// Also manages temporary audio files:
/// - Temp folder for WAV files during recording/playback
/// - Automatic cleanup of old temp files
///
/// Philosophy: Files are the source of truth, databases are indexes.
class FileSystemService {
  static final FileSystemService _instance = FileSystemService._internal();
  factory FileSystemService() => _instance;
  FileSystemService._internal();

  static const String _rootFolderPathKey = 'parachute_root_folder_path';
  static const String _capturesFolderNameKey = 'parachute_captures_folder_name';
  static const String _journalFolderNameKey = 'parachute_journal_folder_name';
  static const String _assetsFolderNameKey = 'parachute_assets_folder_name';
  static const String _sessionsFolderNameKey = 'parachute_sessions_folder_name';
  static const String _secureBookmarkKey = 'parachute_secure_bookmark';

  // Default subfolder names
  static const String _defaultCapturesFolderName = 'captures';
  static const String _defaultJournalFolderName = 'Daily';
  static const String _defaultAssetsFolderName = 'assets';
  static const String _defaultSessionsFolderName = 'agent-sessions';
  static const String _importsFolderName = 'imports';
  static const String _contextsFolderName = 'contexts';
  static const String _tempAudioFolderName = 'parachute_audio_temp';

  // Temp subfolder names with different retention policies
  static const String _tempRecordingsSubfolder = 'recordings'; // Precious - keep longer
  static const String _tempPlaybackSubfolder = 'playback'; // Cache - clean aggressively
  static const String _tempSegmentsSubfolder = 'segments'; // Transient - clean quickly

  // Retention policies for different temp file types
  static const Duration _recordingsTempMaxAge = Duration(days: 7); // Keep recordings 7 days
  static const Duration _playbackTempMaxAge = Duration(hours: 24); // Keep playback cache 24 hours
  static const Duration _segmentsTempMaxAge = Duration(hours: 1); // Clean segments after 1 hour

  String? _rootFolderPath;
  String? _tempAudioPath;
  String _capturesFolderName = _defaultCapturesFolderName;
  String _journalFolderName = _defaultJournalFolderName;
  String _assetsFolderName = _defaultAssetsFolderName;
  String _sessionsFolderName = _defaultSessionsFolderName;
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  // macOS secure bookmarks for persistent folder access
  final SecureBookmarks? _secureBookmarks = Platform.isMacOS ? SecureBookmarks() : null;
  bool _isAccessingSecurityScopedResource = false;

  /// Get the root Parachute folder path
  Future<String> getRootPath() async {
    await initialize();
    return _rootFolderPath!;
  }

  /// Check if we have storage permission on Android
  /// On other platforms, always returns true
  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.manageExternalStorage.status;
    return status.isGranted;
  }

  /// Request storage permission on Android
  /// Returns true if permission was granted
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;

    // Request the permission
    final result = await Permission.manageExternalStorage.request();
    if (result.isGranted) return true;

    // If not granted, we need to open settings
    // The permission_handler will prompt to open settings if permanently denied
    if (result.isPermanentlyDenied) {
      debugPrint('[FileSystemService] Storage permission permanently denied, opening settings');
      await openAppSettings();
    }

    return false;
  }

  /// Get a user-friendly display of the root path
  /// Shows the actual full path so users know exactly where their data is stored
  Future<String> getRootPathDisplay() async {
    final path = await getRootPath();

    // On macOS/Linux, optionally replace home directory with ~ for brevity
    // But keep full path visible so it's not misleading
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && path.startsWith(home)) {
        return path.replaceFirst(home, '~');
      }
    }

    // On Android, show the full path so users know exactly where data is stored
    // This prevents confusion about "External Storage" vs internal app storage
    return path;
  }

  /// Get the captures folder name
  String getCapturesFolderName() {
    return _capturesFolderName;
  }

  /// Get the captures folder path
  Future<String> getCapturesPath() async {
    final root = await getRootPath();
    return '$root/$_capturesFolderName';
  }

  /// Get the journal folder name
  String getJournalFolderName() {
    return _journalFolderName;
  }

  /// Get the journal folder path
  Future<String> getJournalPath() async {
    final root = await getRootPath();
    return '$root/$_journalFolderName';
  }

  // ============================================================
  // Assets Folder (unified media storage)
  // ============================================================

  /// Get the assets folder name
  String getAssetsFolderName() {
    return _assetsFolderName;
  }

  /// Get the assets folder path
  Future<String> getAssetsPath() async {
    final root = await getRootPath();
    return '$root/$_assetsFolderName';
  }

  // ============================================================
  // Sessions Folder (AI chat sessions)
  // ============================================================

  /// Get the sessions folder name
  String getSessionsFolderName() {
    return _sessionsFolderName;
  }

  /// Get the sessions folder path
  Future<String> getSessionsPath() async {
    final root = await getRootPath();
    return '$root/$_sessionsFolderName';
  }

  // ============================================================
  // Imports Folder (ChatGPT/Claude exports, etc.)
  // ============================================================

  /// Get the imports folder name
  String getImportsFolderName() {
    return _importsFolderName;
  }

  /// Get the imports folder path
  Future<String> getImportsPath() async {
    final root = await getRootPath();
    return '$root/$_importsFolderName';
  }

  /// Check if the imports folder exists
  Future<bool> hasImportsFolder() async {
    final path = await getImportsPath();
    return Directory(path).exists();
  }

  /// Ensure imports folder exists
  Future<String> ensureImportsFolderExists() async {
    final path = await getImportsPath();
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  // ============================================================
  // Contexts Folder (project context files from imports)
  // ============================================================

  /// Get the contexts folder name
  String getContextsFolderName() {
    return _contextsFolderName;
  }

  /// Get the contexts folder path
  Future<String> getContextsPath() async {
    final root = await getRootPath();
    return '$root/$_contextsFolderName';
  }

  /// Check if the contexts folder exists
  Future<bool> hasContextsFolder() async {
    final path = await getContextsPath();
    return Directory(path).exists();
  }

  /// Ensure contexts folder exists
  Future<String> ensureContextsFolderExists() async {
    final path = await getContextsPath();
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      debugPrint('[FileSystemService] Created contexts folder: $path');
    }
    return path;
  }

  /// Get the month folder path for assets
  /// Returns path like: ~/Parachute/assets/2025-12
  Future<String> getAssetsMonthPath(DateTime timestamp) async {
    final assetsPath = await getAssetsPath();
    final month = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}';
    return '$assetsPath/$month';
  }

  /// Ensure assets month folder exists
  Future<String> ensureAssetsMonthFolderExists(DateTime timestamp) async {
    final monthPath = await getAssetsMonthPath(timestamp);
    final monthDir = Directory(monthPath);
    if (!await monthDir.exists()) {
      await monthDir.create(recursive: true);
      debugPrint('[FileSystemService] Created assets folder: $monthPath');
    }
    return monthPath;
  }

  /// Generate a unique asset filename with timestamp
  /// Format: YYYY-MM-DD_HHMMSS_{type}.{ext}
  /// e.g., 2025-12-20_143022_audio.wav
  String generateAssetFilename(DateTime timestamp, String type, String extension) {
    final date = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    final time = '${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}${timestamp.second.toString().padLeft(2, '0')}';
    return '${date}_${time}_$type.$extension';
  }

  /// Get full path for a new asset file
  /// Creates the month folder if needed
  Future<String> getNewAssetPath(DateTime timestamp, String type, String extension) async {
    final monthPath = await ensureAssetsMonthFolderExists(timestamp);
    final filename = generateAssetFilename(timestamp, type, extension);
    return '$monthPath/$filename';
  }

  /// Get relative path from vault root to an asset
  /// e.g., "assets/2025-12/2025-12-20_143022_audio.wav"
  String getAssetRelativePath(DateTime timestamp, String filename) {
    final month = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}';
    return '$_assetsFolderName/$month/$filename';
  }

  // ============================================================
  // Legacy Captures Folder Methods (kept for compatibility)
  // ============================================================

  /// Get the month folder path for a timestamp
  /// Returns path like: ~/Parachute/captures/2025-12
  Future<String> getCapturesMonthPath(DateTime timestamp) async {
    final capturesPath = await getCapturesPath();
    final month = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}';
    return '$capturesPath/$month';
  }

  /// Get the audio subfolder path for a timestamp
  /// Returns path like: ~/Parachute/captures/2025-12/_audio
  Future<String> getAudioFolderPath(DateTime timestamp) async {
    final monthPath = await getCapturesMonthPath(timestamp);
    return '$monthPath/_audio';
  }

  /// Ensure month and audio folders exist for a timestamp
  Future<void> ensureMonthFoldersExist(DateTime timestamp) async {
    final monthPath = await getCapturesMonthPath(timestamp);
    final audioPath = await getAudioFolderPath(timestamp);

    final monthDir = Directory(monthPath);
    if (!await monthDir.exists()) {
      await monthDir.create(recursive: true);
      debugPrint('[FileSystemService] Created month folder: $monthPath');
    }

    final audioDir = Directory(audioPath);
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
      debugPrint('[FileSystemService] Created audio folder: $audioPath');
    }
  }

  /// Extract month string from recording ID
  /// Input: "2025-12-15_10-30-22" → Output: "2025-12"
  static String getMonthFromRecordingId(String recordingId) {
    final parts = recordingId.split('_')[0].split('-');
    if (parts.length >= 2) {
      return '${parts[0]}-${parts[1]}';
    }
    return '';
  }

  // ============================================================
  // Temporary Audio File Management
  // ============================================================
  //
  // Folder structure:
  //   parachute_audio_temp/
  //   ├── recordings/   - WAV files during recording (7 day retention)
  //   ├── playback/     - Cached WAV files for playback (24 hour retention)
  //   └── segments/     - Transcription segment files (1 hour retention)
  //
  // This protects precious recordings from aggressive cleanup while
  // still cleaning up transient cache files regularly.
  // ============================================================

  /// Get the root temporary audio folder path
  Future<String> getTempAudioPath() async {
    if (_tempAudioPath != null) {
      return _tempAudioPath!;
    }

    final tempDir = await getTemporaryDirectory();
    _tempAudioPath = '${tempDir.path}/$_tempAudioFolderName';

    // Ensure the directory and subfolders exist
    await _ensureTempFolderStructure();

    return _tempAudioPath!;
  }

  /// Ensure temp folder structure exists
  Future<void> _ensureTempFolderStructure() async {
    if (_tempAudioPath == null) return;

    final subfolders = [
      _tempRecordingsSubfolder,
      _tempPlaybackSubfolder,
      _tempSegmentsSubfolder,
    ];

    for (final subfolder in subfolders) {
      final dir = Directory('$_tempAudioPath/$subfolder');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        debugPrint('[FileSystemService] Created temp subfolder: ${dir.path}');
      }
    }
  }

  /// Generate a path for a recording-in-progress WAV file
  /// These are kept for 7 days to protect against crashes before conversion
  Future<String> getRecordingTempPath() async {
    final tempPath = await getTempAudioPath();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$tempPath/$_tempRecordingsSubfolder/recording_$timestamp.wav';
  }

  /// Generate a path for a playback WAV file (converted from Opus)
  /// Uses a deterministic name based on the source file so we can reuse it
  /// These are cached for 24 hours
  Future<String> getPlaybackTempPath(String sourceOpusPath) async {
    final tempPath = await getTempAudioPath();
    // Create a deterministic filename from the source path
    final sourceFileName = sourceOpusPath.split('/').last.replaceAll('.opus', '');
    return '$tempPath/$_tempPlaybackSubfolder/playback_$sourceFileName.wav';
  }

  /// Generate a path for a transcription segment WAV file
  /// These are transient and cleaned up after 1 hour
  Future<String> getTranscriptionSegmentPath(int segmentIndex) async {
    final tempPath = await getTempAudioPath();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$tempPath/$_tempSegmentsSubfolder/segment_${timestamp}_$segmentIndex.wav';
  }

  /// Generate a path for a generic temp WAV file (goes to segments folder)
  /// [prefix] - Optional prefix for the filename
  Future<String> getTempWavPath({String prefix = 'temp'}) async {
    final tempPath = await getTempAudioPath();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$tempPath/$_tempSegmentsSubfolder/${prefix}_$timestamp.wav';
  }

  /// Clean up old temporary audio files based on retention policies
  /// - recordings: 7 days (precious, might be crash recovery)
  /// - playback: 24 hours (cache, can be regenerated)
  /// - segments: 1 hour (transient, should be cleaned up after transcription)
  /// Call this on app startup
  Future<int> cleanupTempAudioFiles() async {
    var totalDeleted = 0;

    try {
      final tempPath = await getTempAudioPath();

      // Clean each subfolder with its own retention policy
      totalDeleted += await _cleanupTempSubfolder(
        '$tempPath/$_tempRecordingsSubfolder',
        _recordingsTempMaxAge,
        'recordings',
      );

      totalDeleted += await _cleanupTempSubfolder(
        '$tempPath/$_tempPlaybackSubfolder',
        _playbackTempMaxAge,
        'playback',
      );

      totalDeleted += await _cleanupTempSubfolder(
        '$tempPath/$_tempSegmentsSubfolder',
        _segmentsTempMaxAge,
        'segments',
      );

      if (totalDeleted > 0) {
        debugPrint('[FileSystemService] Total temp files cleaned up: $totalDeleted');
      }
    } catch (e) {
      debugPrint('[FileSystemService] Error cleaning up temp files: $e');
    }

    return totalDeleted;
  }

  /// Clean up files in a specific temp subfolder older than maxAge
  Future<int> _cleanupTempSubfolder(String folderPath, Duration maxAge, String folderName) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        return 0;
      }

      final now = DateTime.now();
      var deletedCount = 0;

      await for (final entity in dir.list()) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            final age = now.difference(stat.modified);

            if (age > maxAge) {
              await entity.delete();
              deletedCount++;
              debugPrint('[FileSystemService] Deleted old $folderName temp: ${entity.path.split('/').last}');
            }
          } catch (e) {
            debugPrint('[FileSystemService] Error checking temp file: $e');
          }
        }
      }

      if (deletedCount > 0) {
        debugPrint('[FileSystemService] Cleaned up $deletedCount old $folderName files (max age: ${maxAge.inHours}h)');
      }

      return deletedCount;
    } catch (e) {
      debugPrint('[FileSystemService] Error cleaning $folderName folder: $e');
      return 0;
    }
  }

  /// List unprocessed recordings in temp folder
  /// These are recordings that weren't properly converted to Opus
  /// Returns list of file paths that may need recovery
  Future<List<String>> listOrphanedRecordings() async {
    try {
      final tempPath = await getTempAudioPath();
      final recordingsDir = Directory('$tempPath/$_tempRecordingsSubfolder');

      if (!await recordingsDir.exists()) {
        return [];
      }

      final orphaned = <String>[];
      await for (final entity in recordingsDir.list()) {
        if (entity is File && entity.path.endsWith('.wav')) {
          orphaned.add(entity.path);
        }
      }

      if (orphaned.isNotEmpty) {
        debugPrint('[FileSystemService] Found ${orphaned.length} orphaned recordings in temp');
      }

      return orphaned;
    } catch (e) {
      debugPrint('[FileSystemService] Error listing orphaned recordings: $e');
      return [];
    }
  }

  /// Delete a specific temporary file
  Future<bool> deleteTempFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[FileSystemService] Deleted temp file: ${path.split('/').last}');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[FileSystemService] Error deleting temp file: $e');
      return false;
    }
  }

  /// Clear all temporary audio files (use with caution!)
  /// Only call when no recording/playback is active
  Future<int> clearAllTempAudioFiles() async {
    try {
      final tempPath = await getTempAudioPath();
      final tempDir = Directory(tempPath);

      if (!await tempDir.exists()) {
        return 0;
      }

      var deletedCount = 0;

      // Delete files in all subfolders
      await for (final entity in tempDir.list(recursive: true)) {
        if (entity is File) {
          try {
            await entity.delete();
            deletedCount++;
          } catch (e) {
            debugPrint('[FileSystemService] Error deleting ${entity.path}: $e');
          }
        }
      }

      debugPrint('[FileSystemService] Cleared $deletedCount temp audio files');
      return deletedCount;
    } catch (e) {
      debugPrint('[FileSystemService] Error clearing temp files: $e');
      return 0;
    }
  }

  /// Check if a path is in the temp audio folder
  bool isTempAudioPath(String path) {
    return path.contains(_tempAudioFolderName);
  }

  /// Check if a path is a temp recording (precious, should not be aggressively cleaned)
  bool isTempRecordingPath(String path) {
    return path.contains('$_tempAudioFolderName/$_tempRecordingsSubfolder');
  }

  // ============================================================
  // End Temporary Audio File Management
  // ============================================================

  /// Set custom subfolder names (e.g., for Obsidian vault integration)
  Future<bool> setSubfolderNames({
    String? capturesFolderName,
    String? journalFolderName,
    String? assetsFolderName,
    String? sessionsFolderName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (capturesFolderName != null && capturesFolderName.isNotEmpty) {
        _capturesFolderName = capturesFolderName;
        await prefs.setString(_capturesFolderNameKey, capturesFolderName);
      }

      if (journalFolderName != null && journalFolderName.isNotEmpty) {
        _journalFolderName = journalFolderName;
        await prefs.setString(_journalFolderNameKey, journalFolderName);
      }

      if (assetsFolderName != null && assetsFolderName.isNotEmpty) {
        _assetsFolderName = assetsFolderName;
        await prefs.setString(_assetsFolderNameKey, assetsFolderName);
      }

      if (sessionsFolderName != null && sessionsFolderName.isNotEmpty) {
        _sessionsFolderName = sessionsFolderName;
        await prefs.setString(_sessionsFolderNameKey, sessionsFolderName);
      }

      // Recreate folder structure with new names
      await _ensureFolderStructure();
      return true;
    } catch (e) {
      debugPrint('[FileSystemService] Error setting subfolder names: $e');
      return false;
    }
  }

  /// Initialize the file system
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_initializationFuture != null) {
      return _initializationFuture;
    }

    _initializationFuture = _doInitialize();
    await _initializationFuture;
  }

  Future<void> _doInitialize() async {
    try {
      debugPrint('[FileSystemService] Starting initialization...');
      final prefs = await SharedPreferences.getInstance();

      _rootFolderPath = prefs.getString(_rootFolderPathKey);

      // If no root folder is set, use default
      if (_rootFolderPath == null) {
        _rootFolderPath = await _getDefaultRootPath();
        debugPrint('[FileSystemService] Set default root: $_rootFolderPath');
        await prefs.setString(_rootFolderPathKey, _rootFolderPath!);
      } else {
        // Check if we can access the saved path
        debugPrint('[FileSystemService] Loaded saved root: $_rootFolderPath');

        // On macOS, try to restore access via security-scoped bookmark
        if (Platform.isMacOS && _secureBookmarks != null) {
          final bookmarkData = prefs.getString(_secureBookmarkKey);
          if (bookmarkData != null) {
            try {
              debugPrint('[FileSystemService] Restoring secure bookmark...');
              final resolvedEntity = await _secureBookmarks!.resolveBookmark(bookmarkData);

              // Start accessing the security-scoped resource
              await _secureBookmarks!.startAccessingSecurityScopedResource(resolvedEntity);
              _isAccessingSecurityScopedResource = true;
              debugPrint('[FileSystemService] Secure bookmark restored: ${resolvedEntity.path}');

              // Verify the path matches what we expect
              final resolvedPath = resolvedEntity.path;
              if (resolvedPath != _rootFolderPath) {
                debugPrint('[FileSystemService] Bookmark path differs: $resolvedPath vs $_rootFolderPath');
                _rootFolderPath = resolvedPath;
                await prefs.setString(_rootFolderPathKey, _rootFolderPath!);
              }
            } catch (e) {
              debugPrint('[FileSystemService] Failed to restore secure bookmark: $e');
              // Fall through to regular access check
            }
          }
        }

        // Verify we still have access to the saved path
        // On iOS, the container UUID changes on reinstall
        // On macOS without a bookmark, the user might need to re-select
        if (!_isAccessingSecurityScopedResource) {
          final savedDir = Directory(_rootFolderPath!);
          bool hasAccess = false;

          try {
            // Test if the directory exists and is accessible
            if (await savedDir.exists()) {
              hasAccess = true;
            } else {
              // Try to create it - will fail if container changed
              await savedDir.create(recursive: true);
              hasAccess = true;
            }
          } catch (e) {
            debugPrint('[FileSystemService] Lost access to saved path: $e');
          }

          if (!hasAccess && (Platform.isMacOS || Platform.isIOS)) {
            debugPrint(
              '[FileSystemService] Switching to accessible default location',
            );
            _rootFolderPath = await _getDefaultRootPath();
            await prefs.setString(_rootFolderPathKey, _rootFolderPath!);
          }
        }
      }

      // Load custom subfolder names if set
      _capturesFolderName =
          prefs.getString(_capturesFolderNameKey) ?? _defaultCapturesFolderName;
      _journalFolderName =
          prefs.getString(_journalFolderNameKey) ?? _defaultJournalFolderName;
      _assetsFolderName =
          prefs.getString(_assetsFolderNameKey) ?? _defaultAssetsFolderName;
      _sessionsFolderName =
          prefs.getString(_sessionsFolderNameKey) ?? _defaultSessionsFolderName;

      debugPrint('[FileSystemService] Captures folder: $_capturesFolderName');
      debugPrint('[FileSystemService] Journal folder: $_journalFolderName');
      debugPrint('[FileSystemService] Assets folder: $_assetsFolderName');
      debugPrint('[FileSystemService] Sessions folder: $_sessionsFolderName');

      // Ensure folder structure exists
      await _ensureFolderStructure();

      // Clean up old temp audio files on startup
      await cleanupTempAudioFiles();

      _isInitialized = true;
      _initializationFuture = null;
      debugPrint('[FileSystemService] Initialization complete');
    } catch (e, stackTrace) {
      debugPrint('[FileSystemService] Error during initialization: $e');
      debugPrint('[FileSystemService] Stack trace: $stackTrace');
      _initializationFuture = null;
      rethrow;
    }
  }

  /// Get the default root path based on platform
  Future<String> _getDefaultRootPath() async {
    if (Platform.isMacOS) {
      // macOS: Try to use ~/Parachute first (preferred location)
      // If we can't access it due to sandboxing, fall back to app's Documents
      final home = Platform.environment['HOME'];
      if (home != null) {
        final preferredPath = '$home/Parachute';
        final preferredDir = Directory(preferredPath);

        try {
          // Try to create the directory to test if we have access
          if (!await preferredDir.exists()) {
            await preferredDir.create(recursive: true);
          }

          // Test if we can actually list the directory (this will fail if no permission)
          await preferredDir.list().first.timeout(
            const Duration(milliseconds: 100),
            onTimeout: () => throw Exception('No access'),
          );

          debugPrint('[FileSystemService] Using ~/Parachute (access granted)');
          return preferredPath;
        } catch (e) {
          debugPrint('[FileSystemService] Cannot access ~/Parachute: $e');
          debugPrint(
            '[FileSystemService] User needs to grant access via Settings',
          );
          // Fall through to app Documents directory
        }
      }

      // Fallback: Use app's Documents directory (always accessible)
      final appDir = await getApplicationDocumentsDirectory();
      debugPrint(
        '[FileSystemService] Using app Documents: ${appDir.path}/Parachute',
      );
      return '${appDir.path}/Parachute';
    }

    if (Platform.isLinux) {
      // Linux: Use ~/Parachute (no sandboxing restrictions)
      final home = Platform.environment['HOME'];
      if (home != null) {
        return '$home/Parachute';
      }
      // Fallback to app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      return '${appDir.path}/Parachute';
    }

    if (Platform.isAndroid) {
      // Android: Use external storage directory (user-accessible)
      // This gives /storage/emulated/0/Android/data/{package}/files/
      // which is accessible via file managers and backed up
      try {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          // Create in a parent directory that persists even if app is uninstalled
          // Using the app-specific external directory which is accessible but cleaned on uninstall
          return '${externalDir.path}/Parachute';
        }
      } catch (e) {
        debugPrint('[FileSystemService] Error getting external storage: $e');
      }
    }

    if (Platform.isIOS) {
      // iOS: Use application documents directory
      // This integrates with Files app on iOS
      final appDir = await getApplicationDocumentsDirectory();
      return '${appDir.path}/Parachute';
    }

    // Fallback to app documents directory for other platforms
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/Parachute';
  }

  /// Ensure the folder structure exists
  ///
  /// Note: On macOS, if the vault is outside the app container and we don't
  /// have persistent permissions (security-scoped bookmarks), folder creation
  /// may fail. In this case, we log a warning and continue - the folder
  /// creation is optional for existing vaults.
  Future<void> _ensureFolderStructure() async {
    debugPrint('[FileSystemService] Ensuring folder structure...');

    // Create root
    final root = Directory(_rootFolderPath!);
    try {
      if (!await root.exists()) {
        await root.create(recursive: true);
        debugPrint('[FileSystemService] Created root: ${root.path}');
      }
    } catch (e) {
      debugPrint('[FileSystemService] Could not create root (may lack permissions): $e');
      // If we can't create root, check if it at least exists for reading
      if (!await root.exists()) {
        rethrow; // Can't proceed without root
      }
    }

    // Note: We no longer auto-create the captures folder.
    // New recordings go to Daily/assets/ (journal system).
    // getCapturesPath() still works for reading legacy captures.

    debugPrint('[FileSystemService] Folder structure ready');
  }

  /// Set a custom root folder path (alias for setRootPath)
  /// Used by vault picker during onboarding
  Future<bool> setCustomRootPath(String path) async {
    return setRootPath(path);
  }

  /// Reset to the platform default path
  /// Used by vault picker during onboarding
  Future<bool> resetToDefaultPath() async {
    final defaultPath = await _getDefaultRootPath();
    return setRootPath(defaultPath);
  }

  /// Set a custom root folder path
  ///
  /// [path] - The new root folder path
  /// [migrateFiles] - If true, copies files from old location to new location.
  ///                  If false, just changes the path without copying.
  Future<bool> setRootPath(String path, {bool migrateFiles = true}) async {
    try {
      final oldRootPath = _rootFolderPath;

      // Create new directory structure
      final newDir = Directory(path);
      if (!await newDir.exists()) {
        await newDir.create(recursive: true);
      }

      // If we have an old path and it's different from the new one, optionally migrate files
      if (migrateFiles && oldRootPath != null && oldRootPath != path) {
        final oldDir = Directory(oldRootPath);
        if (await oldDir.exists()) {
          debugPrint(
            '[FileSystemService] Migrating files from $oldRootPath to $path',
          );

          // Copy all contents from old directory to new directory
          await _copyDirectory(oldDir, Directory(path));

          debugPrint(
            '[FileSystemService] Migration complete. Old files remain at $oldRootPath (manual cleanup required)',
          );
        }
      } else if (!migrateFiles) {
        debugPrint(
          '[FileSystemService] Changing root path to $path without file migration',
        );
      }

      // On macOS, create a security-scoped bookmark for persistent access
      if (Platform.isMacOS && _secureBookmarks != null) {
        try {
          // Stop accessing old resource if any
          if (_isAccessingSecurityScopedResource && _rootFolderPath != null) {
            try {
              final oldDir = Directory(_rootFolderPath!);
              await _secureBookmarks!.stopAccessingSecurityScopedResource(oldDir);
            } catch (e) {
              debugPrint('[FileSystemService] Error stopping old resource access: $e');
            }
            _isAccessingSecurityScopedResource = false;
          }

          // Create a new secure bookmark for the directory
          final newDir = Directory(path);
          final bookmarkData = await _secureBookmarks!.bookmark(newDir);
          debugPrint('[FileSystemService] Created secure bookmark for: $path');

          // Save the bookmark for later restoration
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_secureBookmarkKey, bookmarkData);

          // Start accessing the new resource
          await _secureBookmarks!.startAccessingSecurityScopedResource(newDir);
          _isAccessingSecurityScopedResource = true;
        } catch (e) {
          debugPrint('[FileSystemService] Failed to create secure bookmark: $e');
          // Continue anyway - access might work during this session
        }
      }

      // Update the root path
      _rootFolderPath = path;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_rootFolderPathKey, path);

      // Ensure folder structure exists in new location
      await _ensureFolderStructure();

      return true;
    } catch (e) {
      debugPrint('[FileSystemService] Error setting root path: $e');
      return false;
    }
  }

  /// Recursively copy a directory and all its contents
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    // Ensure destination exists
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }

    // List all entities in source
    await for (final entity in source.list(recursive: false)) {
      final String newPath = entity.path.replaceFirst(
        source.path,
        destination.path,
      );

      if (entity is Directory) {
        // Recursively copy subdirectory
        final newDir = Directory(newPath);
        await _copyDirectory(entity, newDir);
      } else if (entity is File) {
        // Copy file
        debugPrint('[FileSystemService] Copying ${entity.path} to $newPath');
        await entity.copy(newPath);
      }
    }
  }

  // ============================================================
  // File Operations (dart:io based)
  // ============================================================

  /// Read a file's contents as string
  Future<String?> readFileAsString(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }
      return await file.readAsString();
    } catch (e) {
      debugPrint('[FileSystemService] Error reading file: $e');
      return null;
    }
  }

  /// Write string content to a file
  Future<bool> writeFileAsString(String filePath, String content) async {
    try {
      final file = File(filePath);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsString(content);
      return true;
    } catch (e) {
      debugPrint('[FileSystemService] Error writing file: $e');
      return false;
    }
  }

  /// Check if a file exists
  Future<bool> fileExists(String filePath) async {
    return File(filePath).exists();
  }

  /// List files in a directory
  Future<List<String>> listDirectory(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];

      final files = <String>[];
      await for (final entity in dir.list()) {
        if (entity is File) {
          files.add(entity.path);
        }
      }
      return files;
    } catch (e) {
      debugPrint('[FileSystemService] Error listing directory: $e');
      return [];
    }
  }

  /// Ensure a directory exists (creates if needed)
  Future<bool> ensureDirectoryExists(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return true;
    } catch (e) {
      debugPrint('[FileSystemService] Error creating directory: $e');
      return false;
    }
  }

  // ============================================================
  // End File Operations
  // ============================================================

  /// Format timestamp for use in filenames (filesystem-safe)
  static String formatTimestampForFilename(DateTime timestamp) {
    return '${timestamp.year}-'
        '${timestamp.month.toString().padLeft(2, '0')}-'
        '${timestamp.day.toString().padLeft(2, '0')}_'
        '${timestamp.hour.toString().padLeft(2, '0')}-'
        '${timestamp.minute.toString().padLeft(2, '0')}-'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }

  /// Parse timestamp from filename
  static DateTime? parseTimestampFromFilename(String filename) {
    try {
      // Extract timestamp part: 2025-10-25_14-30-22
      final regex = RegExp(r'(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})');
      final match = regex.firstMatch(filename);
      if (match == null) return null;

      return DateTime(
        int.parse(match.group(1)!), // year
        int.parse(match.group(2)!), // month
        int.parse(match.group(3)!), // day
        int.parse(match.group(4)!), // hour
        int.parse(match.group(5)!), // minute
        int.parse(match.group(6)!), // second
      );
    } catch (e) {
      debugPrint('[FileSystemService] Error parsing timestamp: $e');
      return null;
    }
  }

}
