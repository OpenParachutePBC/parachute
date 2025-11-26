import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/file_system_service.dart';
import '../../../core/models/space.dart';

/// Local-first storage service for Spaces
///
/// Manages spaces as filesystem directories with space.json metadata files.
/// Each space lives in ~/Parachute/spaces/{space-name}/ with:
/// - space.json: Metadata (id, name, icon, color, timestamps)
/// - CLAUDE.md: System prompt for AI conversations
/// - space.sqlite: Knowledge links (future)
/// - files/: Space-specific files
class SpaceStorageService {
  final FileSystemService _fileSystemService;
  final Uuid _uuid = const Uuid();

  SpaceStorageService({FileSystemService? fileSystemService})
    : _fileSystemService = fileSystemService ?? FileSystemService();

  /// List all spaces from the filesystem
  Future<List<Space>> listSpaces() async {
    try {
      final spacesPath = await _fileSystemService.getSpacesPath();
      final spacesDir = Directory(spacesPath);

      if (!await spacesDir.exists()) {
        debugPrint(
          '[SpaceStorage] Spaces directory does not exist, creating...',
        );
        await spacesDir.create(recursive: true);
        return [];
      }

      final spaces = <Space>[];

      await for (final entity in spacesDir.list()) {
        if (entity is Directory) {
          final name = entity.path.split('/').last;
          // Skip hidden folders
          if (!name.startsWith('.')) {
            try {
              final space = await _readSpaceFromDirectory(entity.path);
              if (space != null) {
                spaces.add(space);
              }
            } catch (e) {
              debugPrint('[SpaceStorage] Error reading space $name: $e');
              // Skip malformed spaces
            }
          }
        }
      }

      // Sort by name
      spaces.sort((a, b) => a.name.compareTo(b.name));

      debugPrint('[SpaceStorage] Found ${spaces.length} spaces');
      return spaces;
    } catch (e) {
      debugPrint('[SpaceStorage] Error listing spaces: $e');
      rethrow;
    }
  }

  /// Get a single space by ID
  Future<Space?> getSpace(String id) async {
    try {
      final spaces = await listSpaces();
      return spaces.where((s) => s.id == id).firstOrNull;
    } catch (e) {
      debugPrint('[SpaceStorage] Error getting space $id: $e');
      return null;
    }
  }

  /// Create a new space
  Future<Space> createSpace({
    required String name,
    String? icon,
    String? color,
  }) async {
    try {
      // Generate ID and sanitize name for filesystem
      final id = _uuid.v4();
      final sanitizedName = _sanitizeForFilesystem(name);
      final timestamp = DateTime.now();

      // Get space path
      final spacesPath = await _fileSystemService.getSpacesPath();
      final spacePath = '$spacesPath/$sanitizedName';
      final spaceDir = Directory(spacePath);

      // Check if space already exists
      if (await spaceDir.exists()) {
        // Find unique name by appending number
        int counter = 1;
        String uniqueName = sanitizedName;
        while (await Directory('$spacesPath/$uniqueName').exists()) {
          uniqueName = '$sanitizedName-$counter';
          counter++;
        }
        debugPrint(
          '[SpaceStorage] Space $sanitizedName exists, using $uniqueName',
        );
        return createSpace(name: uniqueName, icon: icon, color: color);
      }

      // Create directory structure
      await spaceDir.create(recursive: true);
      await Directory('$spacePath/captures').create();
      await Directory('$spacePath/files').create();

      // Create space.json metadata
      final space = Space(
        id: id,
        userId: 'local', // Local-first, no user ID needed
        name: name,
        path: sanitizedName,
        icon: icon ?? '📁',
        color: color,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      await _writeSpaceJson(spacePath, space);

      // Create default CLAUDE.md
      await _createDefaultClaudeMd(spacePath, name);

      debugPrint('[SpaceStorage] Created space: $name at $spacePath');
      return space;
    } catch (e) {
      debugPrint('[SpaceStorage] Error creating space: $e');
      rethrow;
    }
  }

  /// Update a space's metadata
  Future<Space> updateSpace({
    required String id,
    String? name,
    String? icon,
    String? color,
  }) async {
    try {
      // Find existing space
      final existingSpace = await getSpace(id);
      if (existingSpace == null) {
        throw Exception('Space not found: $id');
      }

      // Update fields
      final updatedSpace = existingSpace.copyWith(
        name: name ?? existingSpace.name,
        icon: icon ?? existingSpace.icon,
        color: color ?? existingSpace.color,
        updatedAt: DateTime.now(),
      );

      // Write updated metadata
      final spacesPath = await _fileSystemService.getSpacesPath();
      final spacePath = '$spacesPath/${existingSpace.path}';
      await _writeSpaceJson(spacePath, updatedSpace);

      // If name changed, update CLAUDE.md header
      if (name != null && name != existingSpace.name) {
        await _updateClaudeMdName(spacePath, name);
      }

      debugPrint('[SpaceStorage] Updated space: ${updatedSpace.name}');
      return updatedSpace;
    } catch (e) {
      debugPrint('[SpaceStorage] Error updating space: $e');
      rethrow;
    }
  }

  /// Delete a space and all its contents
  Future<void> deleteSpace(String id) async {
    try {
      // Find space
      final space = await getSpace(id);
      if (space == null) {
        throw Exception('Space not found: $id');
      }

      // Delete directory
      final spacesPath = await _fileSystemService.getSpacesPath();
      final spacePath = '$spacesPath/${space.path}';
      final spaceDir = Directory(spacePath);

      if (await spaceDir.exists()) {
        await spaceDir.delete(recursive: true);
        debugPrint('[SpaceStorage] Deleted space: ${space.name}');
      }
    } catch (e) {
      debugPrint('[SpaceStorage] Error deleting space: $e');
      rethrow;
    }
  }

  /// Read space metadata from directory
  Future<Space?> _readSpaceFromDirectory(String spacePath) async {
    try {
      final spaceJsonFile = File('$spacePath/space.json');

      if (!await spaceJsonFile.exists()) {
        debugPrint('[SpaceStorage] No space.json in $spacePath');
        return null;
      }

      final jsonString = await spaceJsonFile.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      return Space(
        id: json['id'] as String,
        userId: json['userId'] as String? ?? 'local',
        name: json['name'] as String,
        path: spacePath.split('/').last,
        icon: json['icon'] as String?,
        color: json['color'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
    } catch (e) {
      debugPrint('[SpaceStorage] Error reading space from $spacePath: $e');
      return null;
    }
  }

  /// Write space.json metadata file
  Future<void> _writeSpaceJson(String spacePath, Space space) async {
    final spaceJsonFile = File('$spacePath/space.json');
    final json = {
      'id': space.id,
      'userId': space.userId,
      'name': space.name,
      'icon': space.icon,
      'color': space.color,
      'createdAt': space.createdAt.toIso8601String(),
      'updatedAt': space.updatedAt.toIso8601String(),
    };

    await spaceJsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
    );
  }

  /// Create default CLAUDE.md system prompt
  Future<void> _createDefaultClaudeMd(String spacePath, String name) async {
    final claudeMd = File('$spacePath/CLAUDE.md');
    final content =
        '''# $name

This is the system prompt for the **$name** space.

## Purpose

Describe what this space is for and what kind of conversations or work happens here.

## Context

Add any relevant context, guidelines, or information that Claude should know when working in this space.

## Files

Files related to this space are stored in the `files/` folder.

---

*Created: ${DateTime.now().toIso8601String()}*
''';

    await claudeMd.writeAsString(content);
  }

  /// Update CLAUDE.md header when space name changes
  Future<void> _updateClaudeMdName(String spacePath, String newName) async {
    final claudeMd = File('$spacePath/CLAUDE.md');

    if (await claudeMd.exists()) {
      try {
        final content = await claudeMd.readAsString();
        // Replace first # heading
        final updated = content.replaceFirst(
          RegExp(r'^# .*$', multiLine: true),
          '# $newName',
        );
        // Replace **name** in first paragraph
        final finalContent = updated.replaceFirst(
          RegExp(r'\*\*.*?\*\*'),
          '**$newName**',
        );
        await claudeMd.writeAsString(finalContent);
      } catch (e) {
        debugPrint('[SpaceStorage] Error updating CLAUDE.md name: $e');
      }
    }
  }

  /// Sanitize name for use as filesystem directory name
  String _sanitizeForFilesystem(String name) {
    // Replace invalid characters with hyphens
    final sanitized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-_]'), '-')
        .replaceAll(RegExp(r'-+'), '-') // Collapse multiple hyphens
        .replaceAll(RegExp(r'^-|-$'), ''); // Remove leading/trailing hyphens

    return sanitized.isEmpty ? 'space' : sanitized;
  }
}
