import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';

/// Unified file system service for Parachute Daily
///
/// Manages the Daily folder structure (e.g., ~/Parachute/Daily/):
/// - journals/       - Daily journal entries (YYYY-MM-DD.md) - configurable name
/// - assets/         - All media files (audio, images) organized by YYYY-MM
///
/// The root path points directly to the Daily module folder.
/// This is a self-contained, modular design.
///
/// Philosophy: Files are the source of truth, databases are indexes.
class FileSystemService {
  static final FileSystemService _instance = FileSystemService._internal();
  factory FileSystemService() => _instance;
  FileSystemService._internal();

  static const String _rootFolderPathKey = 'parachute_daily_root_path';
  static const String _journalsFolderNameKey = 'parachute_daily_journals_folder';
  static const String _assetsFolderNameKey = 'parachute_daily_assets_folder';
  static const String _secureBookmarkKey = 'parachute_daily_secure_bookmark';
  static const String _userConfiguredKey = 'parachute_daily_user_configured';

  // Default subfolder names
  static const String _defaultJournalsFolderName = 'journals';
  static const String _defaultAssetsFolderName = 'assets';
  static const String _tempAudioFolderName = 'parachute_audio_temp';

  // Temp subfolder names with different retention policies
  static const String _tempRecordingsSubfolder = 'recordings';
  static const String _tempPlaybackSubfolder = 'playback';
  static const String _tempSegmentsSubfolder = 'segments';

  // Retention policies for different temp file types
  static const Duration _recordingsTempMaxAge = Duration(days: 7);
  static const Duration _playbackTempMaxAge = Duration(hours: 24);
  static const Duration _segmentsTempMaxAge = Duration(hours: 1);

  String? _rootFolderPath;
  String? _tempAudioPath;
  String _journalsFolderName = _defaultJournalsFolderName;
  String _assetsFolderName = _defaultAssetsFolderName;
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  // macOS secure bookmarks for persistent folder access
  final SecureBookmarks? _secureBookmarks = Platform.isMacOS ? SecureBookmarks() : null;
  bool _isAccessingSecurityScopedResource = false;

  /// Get the root Daily folder path
  Future<String> getRootPath() async {
    await initialize();
    return _rootFolderPath!;
  }

  /// Check if the user has explicitly configured a path (vs using default)
  /// This is used to determine if onboarding should be shown
  Future<bool> isUserConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_userConfiguredKey) ?? false;
  }

  /// Mark the path as user-configured
  Future<void> markAsConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_userConfiguredKey, true);
  }

  /// Check if we have storage permission on Android
  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.manageExternalStorage.status;
    return status.isGranted;
  }

  /// Request storage permission on Android
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;

    final result = await Permission.manageExternalStorage.request();
    if (result.isGranted) return true;

    if (result.isPermanentlyDenied) {
      debugPrint('[FileSystemService] Storage permission permanently denied, opening settings');
      await openAppSettings();
    }

    return false;
  }

  /// Get a user-friendly display of the root path
  Future<String> getRootPathDisplay() async {
    final path = await getRootPath();

    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && path.startsWith(home)) {
        return path.replaceFirst(home, '~');
      }
    }

    return path;
  }

  // ============================================================
  // Journals Folder
  // ============================================================

  /// Get the journals folder name (empty string = store in root)
  String getJournalFolderName() {
    return _journalsFolderName;
  }

  /// Get the journals folder path
  /// If folder name is empty, returns root path (backwards compat)
  Future<String> getJournalPath() async {
    final root = await getRootPath();
    if (_journalsFolderName.isEmpty) {
      return root;
    }
    return '$root/$_journalsFolderName';
  }

  // ============================================================
  // Assets Folder (unified media storage inside Daily)
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

  /// Get the month folder path for assets
  /// Returns path like: ~/Parachute/Daily/assets/2025-12
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
  String generateAssetFilename(DateTime timestamp, String type, String extension) {
    final date = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    final time = '${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}${timestamp.second.toString().padLeft(2, '0')}';
    return '${date}_${time}_$type.$extension';
  }

  /// Get full path for a new asset file
  Future<String> getNewAssetPath(DateTime timestamp, String type, String extension) async {
    final monthPath = await ensureAssetsMonthFolderExists(timestamp);
    final filename = generateAssetFilename(timestamp, type, extension);
    return '$monthPath/$filename';
  }

  /// Get relative path from root to an asset
  String getAssetRelativePath(DateTime timestamp, String filename) {
    final month = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}';
    return '$_assetsFolderName/$month/$filename';
  }

  // ============================================================
  // Temporary Audio File Management
  // ============================================================

  /// Get the root temporary audio folder path
  Future<String> getTempAudioPath() async {
    if (_tempAudioPath != null) {
      return _tempAudioPath!;
    }

    final tempDir = await getTemporaryDirectory();
    _tempAudioPath = '${tempDir.path}/$_tempAudioFolderName';

    await _ensureTempFolderStructure();

    return _tempAudioPath!;
  }

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
      }
    }
  }

  /// Generate a path for a recording-in-progress WAV file
  Future<String> getRecordingTempPath() async {
    final tempPath = await getTempAudioPath();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$tempPath/$_tempRecordingsSubfolder/recording_$timestamp.wav';
  }

  /// Generate a path for a playback WAV file
  Future<String> getPlaybackTempPath(String sourceOpusPath) async {
    final tempPath = await getTempAudioPath();
    final sourceFileName = sourceOpusPath.split('/').last.replaceAll('.opus', '');
    return '$tempPath/$_tempPlaybackSubfolder/playback_$sourceFileName.wav';
  }

  /// Generate a path for a transcription segment WAV file
  Future<String> getTranscriptionSegmentPath(int segmentIndex) async {
    final tempPath = await getTempAudioPath();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$tempPath/$_tempSegmentsSubfolder/segment_${timestamp}_$segmentIndex.wav';
  }

  /// Generate a path for a generic temp WAV file
  Future<String> getTempWavPath({String prefix = 'temp'}) async {
    final tempPath = await getTempAudioPath();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$tempPath/$_tempSegmentsSubfolder/${prefix}_$timestamp.wav';
  }

  /// Clean up old temporary audio files based on retention policies
  Future<int> cleanupTempAudioFiles() async {
    var totalDeleted = 0;

    try {
      final tempPath = await getTempAudioPath();

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
            }
          } catch (e) {
            debugPrint('[FileSystemService] Error checking temp file: $e');
          }
        }
      }

      return deletedCount;
    } catch (e) {
      debugPrint('[FileSystemService] Error cleaning $folderName folder: $e');
      return 0;
    }
  }

  /// List unprocessed recordings in temp folder
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
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[FileSystemService] Error deleting temp file: $e');
      return false;
    }
  }

  /// Clear all temporary audio files
  Future<int> clearAllTempAudioFiles() async {
    try {
      final tempPath = await getTempAudioPath();
      final tempDir = Directory(tempPath);

      if (!await tempDir.exists()) {
        return 0;
      }

      var deletedCount = 0;

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

  /// Check if a path is a temp recording
  bool isTempRecordingPath(String path) {
    return path.contains('$_tempAudioFolderName/$_tempRecordingsSubfolder');
  }

  // ============================================================
  // Configuration
  // ============================================================

  /// Set custom subfolder names
  Future<bool> setSubfolderNames({
    String? journalsFolderName,
    String? assetsFolderName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (journalsFolderName != null) {
        _journalsFolderName = journalsFolderName;
        await prefs.setString(_journalsFolderNameKey, journalsFolderName);
      }

      if (assetsFolderName != null && assetsFolderName.isNotEmpty) {
        _assetsFolderName = assetsFolderName;
        await prefs.setString(_assetsFolderNameKey, assetsFolderName);
      }

      // Ensure folder structure with new names
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

      if (_rootFolderPath == null) {
        _rootFolderPath = await _getDefaultRootPath();
        debugPrint('[FileSystemService] Set default root: $_rootFolderPath');
        await prefs.setString(_rootFolderPathKey, _rootFolderPath!);
      } else {
        debugPrint('[FileSystemService] Loaded saved root: $_rootFolderPath');

        // On macOS, try to restore access via security-scoped bookmark
        if (Platform.isMacOS && _secureBookmarks != null) {
          final bookmarkData = prefs.getString(_secureBookmarkKey);
          if (bookmarkData != null) {
            try {
              final resolvedEntity = await _secureBookmarks.resolveBookmark(bookmarkData);
              await _secureBookmarks.startAccessingSecurityScopedResource(resolvedEntity);
              _isAccessingSecurityScopedResource = true;

              final resolvedPath = resolvedEntity.path;
              if (resolvedPath != _rootFolderPath) {
                _rootFolderPath = resolvedPath;
                await prefs.setString(_rootFolderPathKey, _rootFolderPath!);
              }
            } catch (e) {
              debugPrint('[FileSystemService] Failed to restore secure bookmark: $e');
            }
          }
        }

        // Verify access
        if (!_isAccessingSecurityScopedResource) {
          final savedDir = Directory(_rootFolderPath!);
          bool hasAccess = false;

          try {
            if (await savedDir.exists()) {
              hasAccess = true;
            } else {
              await savedDir.create(recursive: true);
              hasAccess = true;
            }
          } catch (e) {
            debugPrint('[FileSystemService] Lost access to saved path: $e');
          }

          if (!hasAccess && (Platform.isMacOS || Platform.isIOS)) {
            _rootFolderPath = await _getDefaultRootPath();
            await prefs.setString(_rootFolderPathKey, _rootFolderPath!);
          }
        }
      }

      // Load custom subfolder names
      _journalsFolderName = prefs.getString(_journalsFolderNameKey) ?? _defaultJournalsFolderName;
      _assetsFolderName = prefs.getString(_assetsFolderNameKey) ?? _defaultAssetsFolderName;

      debugPrint('[FileSystemService] Journals folder: ${_journalsFolderName.isEmpty ? "(root)" : _journalsFolderName}');
      debugPrint('[FileSystemService] Assets folder: $_assetsFolderName');

      await _ensureFolderStructure();
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
      final home = Platform.environment['HOME'];
      if (home != null) {
        final preferredPath = '$home/Parachute/Daily';
        final preferredDir = Directory(preferredPath);

        try {
          if (!await preferredDir.exists()) {
            await preferredDir.create(recursive: true);
          }
          return preferredPath;
        } catch (e) {
          debugPrint('[FileSystemService] Cannot access ~/Parachute/Daily: $e');
        }
      }

      final appDir = await getApplicationDocumentsDirectory();
      return '${appDir.path}/Parachute/Daily';
    }

    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        return '$home/Parachute/Daily';
      }
      final appDir = await getApplicationDocumentsDirectory();
      return '${appDir.path}/Parachute/Daily';
    }

    if (Platform.isAndroid) {
      try {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          return '${externalDir.path}/Parachute/Daily';
        }
      } catch (e) {
        debugPrint('[FileSystemService] Error getting external storage: $e');
      }
    }

    if (Platform.isIOS) {
      final appDir = await getApplicationDocumentsDirectory();
      return '${appDir.path}/Parachute/Daily';
    }

    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/Parachute/Daily';
  }

  /// Ensure the folder structure exists
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
      debugPrint('[FileSystemService] Could not create root: $e');
      if (!await root.exists()) {
        rethrow;
      }
    }

    // Create journals folder if specified
    if (_journalsFolderName.isNotEmpty) {
      final journalsDir = Directory('${root.path}/$_journalsFolderName');
      if (!await journalsDir.exists()) {
        await journalsDir.create(recursive: true);
        debugPrint('[FileSystemService] Created journals folder: ${journalsDir.path}');
      }
    }

    // Create assets folder
    final assetsDir = Directory('${root.path}/$_assetsFolderName');
    if (!await assetsDir.exists()) {
      await assetsDir.create(recursive: true);
      debugPrint('[FileSystemService] Created assets folder: ${assetsDir.path}');
    }

    debugPrint('[FileSystemService] Folder structure ready');
  }

  /// Set a custom root folder path
  Future<bool> setCustomRootPath(String path) async {
    return setRootPath(path);
  }

  /// Reset to the platform default path
  Future<bool> resetToDefaultPath() async {
    final defaultPath = await _getDefaultRootPath();
    return setRootPath(defaultPath);
  }

  /// Set a custom root folder path
  Future<bool> setRootPath(String path, {bool migrateFiles = true}) async {
    try {
      final oldRootPath = _rootFolderPath;

      // Create new directory
      final newDir = Directory(path);
      if (!await newDir.exists()) {
        await newDir.create(recursive: true);
      }

      // Migrate files if requested
      if (migrateFiles && oldRootPath != null && oldRootPath != path) {
        final oldDir = Directory(oldRootPath);
        if (await oldDir.exists()) {
          debugPrint('[FileSystemService] Migrating files from $oldRootPath to $path');
          await _copyDirectory(oldDir, Directory(path));
        }
      }

      // On macOS, create security-scoped bookmark
      if (Platform.isMacOS && _secureBookmarks != null) {
        try {
          if (_isAccessingSecurityScopedResource && _rootFolderPath != null) {
            try {
              final oldDir = Directory(_rootFolderPath!);
              await _secureBookmarks.stopAccessingSecurityScopedResource(oldDir);
            } catch (e) {
              debugPrint('[FileSystemService] Error stopping old resource access: $e');
            }
            _isAccessingSecurityScopedResource = false;
          }

          final newDir = Directory(path);
          final bookmarkData = await _secureBookmarks.bookmark(newDir);

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_secureBookmarkKey, bookmarkData);

          await _secureBookmarks.startAccessingSecurityScopedResource(newDir);
          _isAccessingSecurityScopedResource = true;
        } catch (e) {
          debugPrint('[FileSystemService] Failed to create secure bookmark: $e');
        }
      }

      // Update the root path
      _rootFolderPath = path;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_rootFolderPathKey, path);

      // Mark as user-configured
      await prefs.setBool(_userConfiguredKey, true);

      await _ensureFolderStructure();

      return true;
    } catch (e) {
      debugPrint('[FileSystemService] Error setting root path: $e');
      return false;
    }
  }

  /// Recursively copy a directory
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }

    await for (final entity in source.list(recursive: false)) {
      final String newPath = entity.path.replaceFirst(source.path, destination.path);

      if (entity is Directory) {
        final newDir = Directory(newPath);
        await _copyDirectory(entity, newDir);
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  // ============================================================
  // File Operations
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

  /// Ensure a directory exists
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

  /// Format timestamp for use in filenames
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
      final regex = RegExp(r'(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})');
      final match = regex.firstMatch(filename);
      if (match == null) return null;

      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } catch (e) {
      return null;
    }
  }
}
