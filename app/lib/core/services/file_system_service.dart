import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unified file system service for Parachute
///
/// Manages the ~/Parachute/ folder structure:
/// - captures/     - Voice recordings and transcripts
/// - spaces/       - AI chat spaces with conversations
///
/// Philosophy: Files are the source of truth, databases are indexes.
class FileSystemService {
  static final FileSystemService _instance = FileSystemService._internal();
  factory FileSystemService() => _instance;
  FileSystemService._internal();

  static const String _rootFolderPathKey = 'parachute_root_folder_path';
  static const String _capturesFolderNameKey = 'parachute_captures_folder_name';
  static const String _spacesFolderNameKey = 'parachute_spaces_folder_name';
  static const String _hasInitializedKey = 'file_system_initialized';

  // Default subfolder names
  static const String _defaultCapturesFolderName = 'captures';
  static const String _defaultSpacesFolderName = 'spaces';

  String? _rootFolderPath;
  String _capturesFolderName = _defaultCapturesFolderName;
  String _spacesFolderName = _defaultSpacesFolderName;
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  /// Get the root Parachute folder path
  Future<String> getRootPath() async {
    await initialize();
    return _rootFolderPath!;
  }

  /// Get a user-friendly display of the root path
  Future<String> getRootPathDisplay() async {
    final path = await getRootPath();

    // Replace home directory with ~ on Unix-like systems
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && path.startsWith(home)) {
        return path.replaceFirst(home, '~');
      }
    }

    // On Android, show a simpler path
    if (Platform.isAndroid && path.contains('/Android/data/')) {
      // Extract the meaningful part: /storage/emulated/0/Android/data/{package}/files/Parachute
      // Show as: External Storage/Parachute
      final parts = path.split('/');
      final parachuteIndex = parts.lastIndexOf('Parachute');
      if (parachuteIndex != -1) {
        return 'External Storage/Parachute';
      }
    }

    return path;
  }

  /// Get the captures folder name
  String getCapturesFolderName() {
    return _capturesFolderName;
  }

  /// Get the spaces folder name
  String getSpacesFolderName() {
    return _spacesFolderName;
  }

  /// Get the captures folder path
  Future<String> getCapturesPath() async {
    final root = await getRootPath();
    return '$root/$_capturesFolderName';
  }

  /// Get the spaces folder path
  Future<String> getSpacesPath() async {
    final root = await getRootPath();
    return '$root/$_spacesFolderName';
  }

  /// Set custom subfolder names (e.g., for Obsidian vault integration)
  Future<bool> setSubfolderNames({
    String? capturesFolderName,
    String? spacesFolderName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (capturesFolderName != null && capturesFolderName.isNotEmpty) {
        _capturesFolderName = capturesFolderName;
        await prefs.setString(_capturesFolderNameKey, capturesFolderName);
      }

      if (spacesFolderName != null && spacesFolderName.isNotEmpty) {
        _spacesFolderName = spacesFolderName;
        await prefs.setString(_spacesFolderNameKey, spacesFolderName);
      }

      // Recreate folder structure with new names
      await _ensureFolderStructure();
      return true;
    } catch (e) {
      debugPrint('[FileSystemService] Error setting subfolder names: $e');
      return false;
    }
  }

  /// Get path for a specific space
  Future<String> getSpacePath(String spaceName) async {
    final spacesPath = await getSpacesPath();
    return '$spacesPath/$spaceName';
  }

  /// Get conversations folder for a space
  Future<String> getSpaceConversationsPath(String spaceName) async {
    final spacePath = await getSpacePath(spaceName);
    return '$spacePath/conversations';
  }

  /// Get files folder for a space
  Future<String> getSpaceFilesPath(String spaceName) async {
    final spacePath = await getSpacePath(spaceName);
    return '$spacePath/files';
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
      }

      // Load custom subfolder names if set
      _capturesFolderName =
          prefs.getString(_capturesFolderNameKey) ?? _defaultCapturesFolderName;
      _spacesFolderName =
          prefs.getString(_spacesFolderNameKey) ?? _defaultSpacesFolderName;

      debugPrint('[FileSystemService] Captures folder: $_capturesFolderName');
      debugPrint('[FileSystemService] Spaces folder: $_spacesFolderName');

      // Ensure folder structure exists
      await _ensureFolderStructure();

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
    if (Platform.isMacOS || Platform.isLinux) {
      // Use ~/Parachute on desktop
      final home = Platform.environment['HOME'];
      if (home != null) {
        return '$home/Parachute';
      }
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

    // Create spaces folder (using configured name)
    final spacesDir = Directory('${_rootFolderPath!}/$_spacesFolderName');
    if (!await spacesDir.exists()) {
      await spacesDir.create(recursive: true);
      debugPrint(
        '[FileSystemService] Created $_spacesFolderName/: ${spacesDir.path}',
      );
    }

    debugPrint('[FileSystemService] Folder structure ready');
  }

  /// Set a custom root folder path
  Future<bool> setRootPath(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _rootFolderPath = path;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_rootFolderPathKey, path);

      await _ensureFolderStructure();
      return true;
    } catch (e) {
      debugPrint('[FileSystemService] Error setting root path: $e');
      return false;
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

  /// Create a new space folder
  Future<bool> createSpace(String spaceName) async {
    try {
      final spacePath = await getSpacePath(spaceName);
      final spaceDir = Directory(spacePath);

      if (await spaceDir.exists()) {
        debugPrint('[FileSystemService] Space already exists: $spaceName');
        return false;
      }

      await spaceDir.create(recursive: true);

      // Create subdirectories
      await Directory('$spacePath/conversations').create();
      await Directory('$spacePath/files').create();

      // Create default SPACE.md
      final spaceMd = File('$spacePath/SPACE.md');
      await spaceMd.writeAsString(_getDefaultSpaceMd(spaceName));

      // Create .space.json metadata
      final spaceJson = File('$spacePath/.space.json');
      await spaceJson.writeAsString(_getDefaultSpaceJson(spaceName));

      debugPrint('[FileSystemService] Created space: $spaceName');
      return true;
    } catch (e) {
      debugPrint('[FileSystemService] Error creating space: $e');
      return false;
    }
  }

  String _getDefaultSpaceMd(String spaceName) {
    return '''# $spaceName

This is the context file for the **$spaceName** space.

## About This Space

Add information here about what this space is for, relevant context, and any guidelines for conversations in this space.

## Files

Files related to this space are stored in the `files/` folder.

## Conversations

All conversations in this space are stored in the `conversations/` folder.

---

*Last updated: ${DateTime.now().toIso8601String()}*
''';
  }

  String _getDefaultSpaceJson(String spaceName) {
    final now = DateTime.now().toIso8601String();
    return '''{
  "id": "${_generateId()}",
  "name": "$spaceName",
  "createdAt": "$now",
  "updatedAt": "$now",
  "mcpServers": [],
  "icon": "📁",
  "color": "#2E7D32"
}''';
  }

  String _generateId() {
    // Simple UUID-like ID generator
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final random = (DateTime.now().microsecondsSinceEpoch % 1000000)
        .toRadixString(36);
    return '$timestamp-$random';
  }

  /// List all spaces
  Future<List<String>> listSpaces() async {
    try {
      final spacesPath = await getSpacesPath();
      final spacesDir = Directory(spacesPath);

      if (!await spacesDir.exists()) {
        return [];
      }

      final spaces = <String>[];
      await for (final entity in spacesDir.list()) {
        if (entity is Directory) {
          final name = entity.path.split('/').last;
          // Skip hidden folders
          if (!name.startsWith('.')) {
            spaces.add(name);
          }
        }
      }

      return spaces;
    } catch (e) {
      debugPrint('[FileSystemService] Error listing spaces: $e');
      return [];
    }
  }

  /// Delete a space
  Future<bool> deleteSpace(String spaceName) async {
    try {
      final spacePath = await getSpacePath(spaceName);
      final spaceDir = Directory(spacePath);

      if (!await spaceDir.exists()) {
        debugPrint('[FileSystemService] Space does not exist: $spaceName');
        return false;
      }

      await spaceDir.delete(recursive: true);
      debugPrint('[FileSystemService] Deleted space: $spaceName');
      return true;
    } catch (e) {
      debugPrint('[FileSystemService] Error deleting space: $e');
      return false;
    }
  }

  /// Check if a space exists
  Future<bool> spaceExists(String spaceName) async {
    final spacePath = await getSpacePath(spaceName);
    final spaceDir = Directory(spacePath);
    return await spaceDir.exists();
  }
}
