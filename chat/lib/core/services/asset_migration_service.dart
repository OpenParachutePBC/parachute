import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'file_system_service.dart';

/// Service for migrating audio files from legacy locations to the unified assets folder.
///
/// Legacy locations:
/// - captures/YYYY-MM/_audio/*.wav - Old recording audio files
/// - Daily/assets/*.wav - Old journal audio files
///
/// New location:
/// - assets/YYYY-MM/*.wav - Unified asset storage
///
/// This migration runs once on app startup and updates markdown references.
class AssetMigrationService {
  static const String _migrationCompleteKey = 'asset_migration_v1_complete';

  final FileSystemService _fileSystem;

  AssetMigrationService(this._fileSystem);

  /// Check if migration has already been completed
  Future<bool> isMigrationComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_migrationCompleteKey) ?? false;
  }

  /// Run the migration if not already complete
  /// Returns the number of files migrated
  Future<int> runMigrationIfNeeded() async {
    if (await isMigrationComplete()) {
      debugPrint('[AssetMigration] Migration already complete');
      return 0;
    }

    debugPrint('[AssetMigration] Starting asset migration...');
    int totalMigrated = 0;

    try {
      // Migrate from captures/_audio/ folders
      totalMigrated += await _migrateCapturesAudio();

      // Migrate from Daily/assets/ folder
      totalMigrated += await _migrateJournalAssets();

      // Mark migration as complete
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_migrationCompleteKey, true);

      debugPrint('[AssetMigration] Migration complete. Migrated $totalMigrated files.');
      return totalMigrated;
    } catch (e, st) {
      debugPrint('[AssetMigration] Migration error: $e');
      debugPrint('[AssetMigration] Stack trace: $st');
      return totalMigrated;
    }
  }

  /// Migrate audio files from captures/YYYY-MM/_audio/ to assets/YYYY-MM/
  Future<int> _migrateCapturesAudio() async {
    int migrated = 0;

    try {
      final capturesPath = await _fileSystem.getCapturesPath();
      final capturesDir = Directory(capturesPath);

      if (!await capturesDir.exists()) {
        debugPrint('[AssetMigration] No captures directory found');
        return 0;
      }

      final monthPattern = RegExp(r'^\d{4}-\d{2}$');

      await for (final entity in capturesDir.list()) {
        if (entity is Directory) {
          final folderName = entity.path.split('/').last;
          if (monthPattern.hasMatch(folderName)) {
            // This is a month folder - check for _audio subfolder
            final audioDir = Directory('${entity.path}/_audio');
            if (await audioDir.exists()) {
              await for (final audioEntity in audioDir.list()) {
                if (audioEntity is File && _isAudioFile(audioEntity.path)) {
                  final success = await _migrateAudioFile(audioEntity, folderName);
                  if (success) migrated++;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AssetMigration] Error migrating captures audio: $e');
    }

    debugPrint('[AssetMigration] Migrated $migrated files from captures/_audio/');
    return migrated;
  }

  /// Migrate audio files from Daily/assets/ to assets/YYYY-MM/
  Future<int> _migrateJournalAssets() async {
    int migrated = 0;

    try {
      final journalPath = await _fileSystem.getJournalPath();
      final journalAssetsDir = Directory('$journalPath/assets');

      if (!await journalAssetsDir.exists()) {
        debugPrint('[AssetMigration] No journal assets directory found');
        return 0;
      }

      await for (final entity in journalAssetsDir.list()) {
        if (entity is File && _isAudioFile(entity.path)) {
          // Parse date from filename to determine target month folder
          final filename = entity.path.split('/').last;
          final timestamp = _parseTimestampFromFilename(filename);

          if (timestamp != null) {
            final monthStr = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}';
            final success = await _migrateAudioFile(entity, monthStr);
            if (success) migrated++;
          } else {
            // Can't parse timestamp - use current month as fallback
            final now = DateTime.now();
            final monthStr = '${now.year}-${now.month.toString().padLeft(2, '0')}';
            final success = await _migrateAudioFile(entity, monthStr);
            if (success) migrated++;
          }
        }
      }
    } catch (e) {
      debugPrint('[AssetMigration] Error migrating journal assets: $e');
    }

    debugPrint('[AssetMigration] Migrated $migrated files from journal assets/');
    return migrated;
  }

  /// Migrate a single audio file to the unified assets folder
  Future<bool> _migrateAudioFile(File sourceFile, String monthStr) async {
    try {
      final filename = sourceFile.path.split('/').last;
      final assetsPath = await _fileSystem.getAssetsPath();
      final destDir = Directory('$assetsPath/$monthStr');

      // Ensure destination directory exists
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      final destPath = '${destDir.path}/$filename';
      final destFile = File(destPath);

      // Skip if destination already exists
      if (await destFile.exists()) {
        debugPrint('[AssetMigration] Skipping (exists): $filename');
        return false;
      }

      // Copy the file (don't delete source yet in case of issues)
      await sourceFile.copy(destPath);
      debugPrint('[AssetMigration] Migrated: $filename -> $monthStr/');

      // Update markdown references
      await _updateMarkdownReferences(sourceFile.path, destPath, monthStr, filename);

      return true;
    } catch (e) {
      debugPrint('[AssetMigration] Error migrating ${sourceFile.path}: $e');
      return false;
    }
  }

  /// Update markdown files to point to the new asset location
  Future<void> _updateMarkdownReferences(
    String oldPath,
    String newPath,
    String monthStr,
    String filename,
  ) async {
    try {
      // Determine old relative path patterns to search for
      final oldPatterns = <String>[];

      // Pattern for captures/_audio/
      if (oldPath.contains('/_audio/')) {
        oldPatterns.add('captures/$monthStr/_audio/$filename');
        oldPatterns.add('$monthStr/_audio/$filename');
        oldPatterns.add('_audio/$filename');
      }

      // Pattern for Daily/assets/
      final journalFolderName = _fileSystem.getJournalFolderName();
      if (oldPath.contains('/assets/')) {
        oldPatterns.add('$journalFolderName/assets/$filename');
      }

      // New relative path
      final newRelativePath = 'assets/$monthStr/$filename';

      // Search and update markdown files
      await _updateCapturesMarkdown(oldPatterns, newRelativePath);
      await _updateJournalMarkdown(oldPatterns, newRelativePath);
    } catch (e) {
      debugPrint('[AssetMigration] Error updating markdown references: $e');
    }
  }

  /// Update captures markdown files
  Future<void> _updateCapturesMarkdown(List<String> oldPatterns, String newRelativePath) async {
    try {
      final capturesPath = await _fileSystem.getCapturesPath();
      final capturesDir = Directory(capturesPath);

      if (!await capturesDir.exists()) return;

      await for (final entity in capturesDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.md')) {
          await _updateFileReferences(entity, oldPatterns, newRelativePath);
        }
      }
    } catch (e) {
      debugPrint('[AssetMigration] Error updating captures markdown: $e');
    }
  }

  /// Update journal markdown files
  Future<void> _updateJournalMarkdown(List<String> oldPatterns, String newRelativePath) async {
    try {
      final journalPath = await _fileSystem.getJournalPath();
      final journalDir = Directory(journalPath);

      if (!await journalDir.exists()) return;

      await for (final entity in journalDir.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          await _updateFileReferences(entity, oldPatterns, newRelativePath);
        }
      }
    } catch (e) {
      debugPrint('[AssetMigration] Error updating journal markdown: $e');
    }
  }

  /// Update a single file's references
  Future<void> _updateFileReferences(
    File file,
    List<String> oldPatterns,
    String newRelativePath,
  ) async {
    try {
      String content = await file.readAsString();
      bool modified = false;

      for (final oldPattern in oldPatterns) {
        if (content.contains(oldPattern)) {
          content = content.replaceAll(oldPattern, newRelativePath);
          modified = true;
          debugPrint('[AssetMigration] Updated reference in: ${file.path.split('/').last}');
        }
      }

      if (modified) {
        await file.writeAsString(content);
      }
    } catch (e) {
      debugPrint('[AssetMigration] Error updating file ${file.path}: $e');
    }
  }

  /// Check if a file is an audio file
  bool _isAudioFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.wav') ||
        lower.endsWith('.opus') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.aac');
  }

  /// Parse timestamp from audio filename
  /// Supports formats:
  /// - 2025-12-20_14-30-22.wav
  /// - 2025-12-20_14:30.wav (journal format)
  DateTime? _parseTimestampFromFilename(String filename) {
    // Try standard format: 2025-12-20_14-30-22
    final standardRegex = RegExp(r'(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})');
    var match = standardRegex.firstMatch(filename);
    if (match != null) {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    }

    // Try journal format: 2025-12-20_14:30
    final journalRegex = RegExp(r'(\d{4})-(\d{2})-(\d{2})_(\d{2}):(\d{2})');
    match = journalRegex.firstMatch(filename);
    if (match != null) {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
      );
    }

    // Try date only: 2025-12-20
    final dateOnlyRegex = RegExp(r'(\d{4})-(\d{2})-(\d{2})');
    match = dateOnlyRegex.firstMatch(filename);
    if (match != null) {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    }

    return null;
  }

  /// Force re-run migration (for debugging/testing)
  Future<void> resetMigration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_migrationCompleteKey);
    debugPrint('[AssetMigration] Migration reset - will run again on next startup');
  }
}
