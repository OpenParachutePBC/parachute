import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Service for managing knowledge links between captures and spaces
///
/// Each space has its own space_links.jsonl file with:
/// - One JSON object per line
/// - Links captures to this space with context and metadata
/// - Git-friendly: line-by-line diffs, easy merges
///
/// Philosophy: Captures are canonical (in ~/Parachute/captures/), spaces
/// just reference them with their own context and organization.
class SpaceKnowledgeService {
  final Uuid _uuid = const Uuid();

  // In-memory cache of links per space (space_path -> List<LinkedCapture>)
  final Map<String, List<LinkedCapture>> _linkCache = {};

  SpaceKnowledgeService();

  /// Get the JSONL file path for a space
  String _getJsonlPath(String spacePath) {
    return p.join(spacePath, 'space_links.jsonl');
  }

  /// Load links from JSONL file into cache
  Future<List<LinkedCapture>> _loadLinks(String spacePath) async {
    // Return cached if available
    if (_linkCache.containsKey(spacePath)) {
      return _linkCache[spacePath]!;
    }

    final jsonlPath = _getJsonlPath(spacePath);
    final file = File(jsonlPath);

    if (!await file.exists()) {
      debugPrint('[SpaceKnowledge] No links file yet for $spacePath');
      _linkCache[spacePath] = [];
      return [];
    }

    try {
      final lines = await file.readAsLines();
      final links = <LinkedCapture>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          links.add(LinkedCapture.fromJson(json));
        } catch (e) {
          debugPrint('[SpaceKnowledge] Error parsing line: $e');
        }
      }

      _linkCache[spacePath] = links;
      debugPrint(
        '[SpaceKnowledge] Loaded ${links.length} links from $spacePath',
      );
      return links;
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error loading links: $e');
      _linkCache[spacePath] = [];
      return [];
    }
  }

  /// Write links to JSONL file
  Future<void> _writeLinks(String spacePath, List<LinkedCapture> links) async {
    final jsonlPath = _getJsonlPath(spacePath);
    final file = File(jsonlPath);

    // Ensure directory exists
    await file.parent.create(recursive: true);

    try {
      // Write one JSON object per line
      final lines = links.map((link) => jsonEncode(link.toJson())).join('\n');
      await file.writeAsString(lines + (links.isNotEmpty ? '\n' : ''));

      // Update cache
      _linkCache[spacePath] = links;

      debugPrint('[SpaceKnowledge] Wrote ${links.length} links to $spacePath');
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error writing links: $e');
      rethrow;
    }
  }

  /// Link a capture to a space
  Future<void> linkCaptureToSpace({
    required String spaceId,
    required String spacePath,
    required String captureId,
    required String notePath,
    String? context,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final links = await _loadLinks(spacePath);
      final now = DateTime.now();

      // Check if already linked (replace if so)
      final existingIndex = links.indexWhere(
        (link) => link.captureId == captureId,
      );

      final newLink = LinkedCapture(
        id: existingIndex >= 0 ? links[existingIndex].id : _uuid.v4(),
        captureId: captureId,
        notePath: notePath,
        linkedAt: existingIndex >= 0 ? links[existingIndex].linkedAt : now,
        context: context,
        tags: tags,
        lastReferenced: now,
        metadata: metadata,
      );

      if (existingIndex >= 0) {
        links[existingIndex] = newLink;
      } else {
        links.add(newLink);
      }

      await _writeLinks(spacePath, links);

      debugPrint(
        '[SpaceKnowledge] Linked capture $captureId to space $spaceId',
      );
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error linking capture: $e');
      rethrow;
    }
  }

  /// Unlink a capture from a space
  Future<void> unlinkCaptureFromSpace({
    required String spacePath,
    required String captureId,
  }) async {
    try {
      final links = await _loadLinks(spacePath);
      links.removeWhere((link) => link.captureId == captureId);
      await _writeLinks(spacePath, links);

      debugPrint('[SpaceKnowledge] Unlinked capture $captureId');
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error unlinking capture: $e');
      rethrow;
    }
  }

  /// Update context for a linked capture
  Future<void> updateCaptureContext({
    required String spacePath,
    required String captureId,
    String? context,
    List<String>? tags,
  }) async {
    try {
      final links = await _loadLinks(spacePath);
      final index = links.indexWhere((link) => link.captureId == captureId);

      if (index < 0) {
        debugPrint('[SpaceKnowledge] Capture not linked: $captureId');
        return;
      }

      final link = links[index];
      links[index] = LinkedCapture(
        id: link.id,
        captureId: link.captureId,
        notePath: link.notePath,
        linkedAt: link.linkedAt,
        context: context ?? link.context,
        tags: tags ?? link.tags,
        lastReferenced: DateTime.now(),
        metadata: link.metadata,
      );

      await _writeLinks(spacePath, links);

      debugPrint('[SpaceKnowledge] Updated capture $captureId context');
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error updating capture context: $e');
      rethrow;
    }
  }

  /// Get all captures linked to a space
  Future<List<LinkedCapture>> getLinkedCaptures({
    required String spacePath,
    int? limit,
    int? offset,
  }) async {
    try {
      final links = await _loadLinks(spacePath);

      // Sort by linkedAt descending
      links.sort((a, b) => b.linkedAt.compareTo(a.linkedAt));

      // Apply pagination
      final start = offset ?? 0;
      final end = limit != null ? start + limit : links.length;

      return links.sublist(
        start.clamp(0, links.length),
        end.clamp(0, links.length),
      );
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error getting linked captures: $e');
      return [];
    }
  }

  /// Check if a capture is linked to a space
  Future<bool> isCaptureLinked({
    required String spacePath,
    required String captureId,
  }) async {
    try {
      final links = await _loadLinks(spacePath);
      return links.any((link) => link.captureId == captureId);
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error checking if capture linked: $e');
      return false;
    }
  }

  /// Get linked capture details
  Future<LinkedCapture?> getLinkedCapture({
    required String spacePath,
    required String captureId,
  }) async {
    try {
      final links = await _loadLinks(spacePath);
      return links.firstWhere(
        (link) => link.captureId == captureId,
        orElse: () => throw StateError('Not found'),
      );
    } catch (e) {
      return null;
    }
  }

  /// Get statistics for a space
  Future<SpaceStats> getSpaceStats({required String spacePath}) async {
    try {
      final links = await _loadLinks(spacePath);

      if (links.isEmpty) {
        return SpaceStats(noteCount: 0);
      }

      // Find most recent lastReferenced
      DateTime? lastReferenced;
      for (final link in links) {
        if (link.lastReferenced != null) {
          if (lastReferenced == null ||
              link.lastReferenced!.isAfter(lastReferenced)) {
            lastReferenced = link.lastReferenced;
          }
        }
      }

      return SpaceStats(
        noteCount: links.length,
        lastReferenced: lastReferenced,
      );
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error getting space stats: $e');
      return SpaceStats(noteCount: 0);
    }
  }

  /// Search captures by tags
  Future<List<LinkedCapture>> searchByTags({
    required String spacePath,
    required List<String> tags,
  }) async {
    try {
      final links = await _loadLinks(spacePath);

      // Filter by tags (match any)
      final filtered = links.where((link) {
        if (link.tags == null || link.tags!.isEmpty) return false;
        return tags.any((tag) => link.tags!.contains(tag));
      }).toList();

      // Sort by linkedAt descending
      filtered.sort((a, b) => b.linkedAt.compareTo(a.linkedAt));

      return filtered;
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error searching by tags: $e');
      return [];
    }
  }

  /// Clear cache for a space (force reload)
  void clearCacheForSpace(String spacePath) {
    _linkCache.remove(spacePath);
    debugPrint('[SpaceKnowledge] Cleared cache for $spacePath');
  }

  /// Clear all caches
  void clearAllCaches() {
    _linkCache.clear();
    debugPrint('[SpaceKnowledge] Cleared all caches');
  }

  /// Move a capture into a sphere (actually moves files to sphere/captures/)
  ///
  /// Unlike linking, this physically moves the .md and audio files into the
  /// sphere's captures folder. The capture becomes "owned" by this sphere.
  ///
  /// Returns the new capture ID (may change if file already exists in target).
  Future<String> moveCaptureToSpace({
    required String spacePath,
    required String captureId,
    required String sourcePath,
    String? context,
    List<String>? tags,
  }) async {
    try {
      final targetCapturesDir = Directory(p.join(spacePath, 'captures'));
      if (!await targetCapturesDir.exists()) {
        await targetCapturesDir.create(recursive: true);
      }

      // Find source files (md, opus, wav)
      final sourceDir = Directory(p.dirname(sourcePath));
      final baseName = captureId;

      final filesToMove = <String, String>{};  // source -> target

      // Check for each file type
      for (final ext in ['.md', '.opus', '.wav', '.json']) {
        final sourceFile = File(p.join(sourceDir.path, '$baseName$ext'));
        if (await sourceFile.exists()) {
          final targetPath = p.join(targetCapturesDir.path, '$baseName$ext');
          filesToMove[sourceFile.path] = targetPath;
        }
      }

      if (filesToMove.isEmpty) {
        throw Exception('No capture files found for: $captureId');
      }

      // Check if any target files already exist
      String finalCaptureId = captureId;
      bool needsRename = false;
      for (final targetPath in filesToMove.values) {
        if (await File(targetPath).exists()) {
          needsRename = true;
          break;
        }
      }

      // If files exist, generate new unique ID
      if (needsRename) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        finalCaptureId = '${captureId}_$timestamp';
        // Update file paths with new ID
        final updatedMoves = <String, String>{};
        for (final entry in filesToMove.entries) {
          final ext = p.extension(entry.key);
          final newTarget = p.join(targetCapturesDir.path, '$finalCaptureId$ext');
          updatedMoves[entry.key] = newTarget;
        }
        filesToMove.clear();
        filesToMove.addAll(updatedMoves);
      }

      // Move files
      for (final entry in filesToMove.entries) {
        final sourceFile = File(entry.key);
        await sourceFile.rename(entry.value);
        debugPrint('[SpaceKnowledge] Moved ${entry.key} -> ${entry.value}');
      }

      // Add to space_links.jsonl with isMoved flag
      final newNotePath = p.join(targetCapturesDir.path, '$finalCaptureId.md');
      final links = await _loadLinks(spacePath);
      final now = DateTime.now();

      final newLink = LinkedCapture(
        id: _uuid.v4(),
        captureId: finalCaptureId,
        notePath: newNotePath,
        linkedAt: now,
        context: context,
        tags: tags,
        lastReferenced: now,
        metadata: {'isMoved': true, 'originalId': captureId},
      );

      links.add(newLink);
      await _writeLinks(spacePath, links);

      debugPrint(
        '[SpaceKnowledge] Moved capture $captureId to $spacePath as $finalCaptureId',
      );
      return finalCaptureId;
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error moving capture: $e');
      rethrow;
    }
  }

  /// Get all captures that live in a sphere's captures folder
  ///
  /// Unlike getLinkedCaptures which returns references, this returns captures
  /// that are physically stored in the sphere/captures/ directory.
  Future<List<String>> getSphereCaptureIds({required String spacePath}) async {
    try {
      final capturesDir = Directory(p.join(spacePath, 'captures'));
      if (!await capturesDir.exists()) {
        return [];
      }

      final captureIds = <String>[];
      await for (final entity in capturesDir.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          final fileName = p.basenameWithoutExtension(entity.path);
          captureIds.add(fileName);
        }
      }

      return captureIds;
    } catch (e) {
      debugPrint('[SpaceKnowledge] Error getting sphere captures: $e');
      return [];
    }
  }
}

/// Represents a capture linked to a space
class LinkedCapture {
  final String id;
  final String captureId;
  final String notePath;
  final DateTime linkedAt;
  final String? context;
  final List<String>? tags;
  final DateTime? lastReferenced;
  final Map<String, dynamic>? metadata;

  LinkedCapture({
    required this.id,
    required this.captureId,
    required this.notePath,
    required this.linkedAt,
    this.context,
    this.tags,
    this.lastReferenced,
    this.metadata,
  });

  factory LinkedCapture.fromJson(Map<String, dynamic> json) {
    return LinkedCapture(
      id: json['id'] as String,
      captureId: json['captureId'] as String,
      notePath: json['notePath'] as String,
      linkedAt: DateTime.parse(json['linkedAt'] as String),
      context: json['context'] as String?,
      tags: json['tags'] != null
          ? List<String>.from(json['tags'] as List)
          : null,
      lastReferenced: json['lastReferenced'] != null
          ? DateTime.parse(json['lastReferenced'] as String)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'captureId': captureId,
      'notePath': notePath,
      'linkedAt': linkedAt.toIso8601String(),
      if (context != null) 'context': context,
      if (tags != null && tags!.isNotEmpty) 'tags': tags,
      if (lastReferenced != null)
        'lastReferenced': lastReferenced!.toIso8601String(),
      if (metadata != null && metadata!.isNotEmpty) 'metadata': metadata,
    };
  }
}

/// Space statistics
class SpaceStats {
  final int noteCount;
  final DateTime? lastReferenced;

  SpaceStats({required this.noteCount, this.lastReferenced});
}
