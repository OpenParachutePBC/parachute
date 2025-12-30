import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'file_system_service.dart';

/// Service for migrating audio files within the Chat module's assets folder.
///
/// This handles the case where audio files might be in the flat assets folder
/// instead of being organized by month (assets/YYYY-MM/).
///
/// This migration runs once on app startup.
class AssetMigrationService {
  static const String _migrationCompleteKey = 'chat_asset_migration_v1_complete';

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
      // Migrate audio files from flat assets folder to month folders
      totalMigrated += await _migrateAssetsToMonthFolders();

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

  /// Migrate audio files from flat assets/ folder to assets/YYYY-MM/
  Future<int> _migrateAssetsToMonthFolders() async {
    int migrated = 0;

    try {
      final assetsPath = await _fileSystem.getAssetsPath();
      final assetsDir = Directory(assetsPath);

      if (!await assetsDir.exists()) {
        debugPrint('[AssetMigration] No assets directory found');
        return 0;
      }

      // Look for audio files directly in the assets folder (not in month subfolders)
      await for (final entity in assetsDir.list()) {
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
      debugPrint('[AssetMigration] Error migrating assets: $e');
    }

    debugPrint('[AssetMigration] Migrated $migrated audio files to month folders');
    return migrated;
  }

  /// Migrate a single audio file to a month subfolder
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

      // Move the file to the month folder
      await sourceFile.rename(destPath);
      debugPrint('[AssetMigration] Migrated: $filename -> $monthStr/');

      return true;
    } catch (e) {
      debugPrint('[AssetMigration] Error migrating ${sourceFile.path}: $e');
      return false;
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
  /// - 2025-12-20_143022_audio.wav
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

    // Try compact format: 2025-12-20_143022
    final compactRegex = RegExp(r'(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})(\d{2})');
    match = compactRegex.firstMatch(filename);
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
