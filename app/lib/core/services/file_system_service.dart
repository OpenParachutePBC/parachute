import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unified file system service for Parachute
///
/// Manages the ~/Parachute/ folder structure:
/// - captures/     - Voice recordings and transcripts
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

  // Default subfolder names
  static const String _defaultCapturesFolderName = 'captures';
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
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  /// Get the root Parachute folder path
  Future<String> getRootPath() async {
    await initialize();
    return _rootFolderPath!;
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
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (capturesFolderName != null && capturesFolderName.isNotEmpty) {
        _capturesFolderName = capturesFolderName;
        await prefs.setString(_capturesFolderNameKey, capturesFolderName);
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

        // Verify we still have access to the saved path
        // On iOS, the container UUID changes on reinstall
        // On macOS, the user might revoke folder access
        if (Platform.isMacOS || Platform.isIOS) {
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

          if (!hasAccess) {
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

      debugPrint('[FileSystemService] Captures folder: $_capturesFolderName');

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
  Future<void> _ensureFolderStructure() async {
    debugPrint('[FileSystemService] Ensuring folder structure...');

    // Create root
    final root = Directory(_rootFolderPath!);
    if (!await root.exists()) {
      await root.create(recursive: true);
      debugPrint('[FileSystemService] Created root: ${root.path}');
    }

    // Create captures folder (using configured name)
    final capturesDir = Directory('${_rootFolderPath!}/$_capturesFolderName');
    if (!await capturesDir.exists()) {
      await capturesDir.create(recursive: true);
      debugPrint(
        '[FileSystemService] Created $_capturesFolderName/: ${capturesDir.path}',
      );
    }

    debugPrint('[FileSystemService] Folder structure ready');
  }

  /// Set a custom root folder path and migrate existing files
  Future<bool> setRootPath(String path) async {
    try {
      final oldRootPath = _rootFolderPath;

      // Create new directory structure
      final newDir = Directory(path);
      if (!await newDir.exists()) {
        await newDir.create(recursive: true);
      }

      // If we have an old path and it's different from the new one, migrate files
      if (oldRootPath != null && oldRootPath != path) {
        final oldDir = Directory(oldRootPath);
        if (await oldDir.exists()) {
          debugPrint(
            '[FileSystemService] Migrating files from $oldRootPath to $path',
          );

          // Copy all contents from old directory to new directory
          await _copyDirectory(oldDir, newDir);

          debugPrint(
            '[FileSystemService] Migration complete. Old files remain at $oldRootPath (manual cleanup required)',
          );
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
