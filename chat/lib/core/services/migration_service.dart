import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';
import '../services/file_system_service.dart';

/// Base class for data migrations.
///
/// Extend this class to create new migrations. Each migration should:
/// 1. Have a unique [id] (e.g., 'v1_assets_to_entries')
/// 2. Implement [migrate] to perform the actual migration
/// 3. Optionally implement [canRun] to check if migration is applicable
abstract class Migration {
  /// Unique identifier for this migration
  String get id;

  /// Human-readable description of what this migration does
  String get description;

  /// Check if this migration can/should run
  /// Override to add custom checks (e.g., check if old format exists)
  Future<bool> canRun() async => true;

  /// Perform the migration
  /// Returns the number of items migrated
  Future<int> migrate();
}

/// Result of running a migration
class MigrationResult {
  final String migrationId;
  final bool success;
  final int itemsMigrated;
  final String? error;
  final DateTime timestamp;

  MigrationResult({
    required this.migrationId,
    required this.success,
    required this.itemsMigrated,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() =>
      'MigrationResult($migrationId: ${success ? "success" : "failed"}, items: $itemsMigrated${error != null ? ", error: $error" : ""})';
}

/// Service for managing and running data migrations.
///
/// Usage:
/// ```dart
/// final migrationService = MigrationService(fileSystemService);
/// final results = await migrationService.runPendingMigrations();
/// ```
class MigrationService {
  static const String _migrationsKey = 'completed_migrations';

  // FileSystemService parameter kept for API consistency (migrations use it directly)
  MigrationService(FileSystemService _);

  /// Get list of completed migration IDs
  Future<Set<String>> getCompletedMigrations() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_migrationsKey) ?? [];
    return list.toSet();
  }

  /// Mark a migration as completed
  Future<void> markCompleted(String migrationId) async {
    final prefs = await SharedPreferences.getInstance();
    final completed = await getCompletedMigrations();
    completed.add(migrationId);
    await prefs.setStringList(_migrationsKey, completed.toList());
  }

  /// Check if a migration has been completed
  Future<bool> isCompleted(String migrationId) async {
    final completed = await getCompletedMigrations();
    return completed.contains(migrationId);
  }

  /// Run a specific migration
  Future<MigrationResult> runMigration(Migration migration) async {
    debugPrint('[MigrationService] Running migration: ${migration.id}');

    try {
      // Check if already completed
      if (await isCompleted(migration.id)) {
        debugPrint('[MigrationService] Migration already completed: ${migration.id}');
        return MigrationResult(
          migrationId: migration.id,
          success: true,
          itemsMigrated: 0,
          error: 'Already completed',
        );
      }

      // Check if migration can run
      if (!await migration.canRun()) {
        debugPrint('[MigrationService] Migration cannot run: ${migration.id}');
        return MigrationResult(
          migrationId: migration.id,
          success: false,
          itemsMigrated: 0,
          error: 'Migration conditions not met',
        );
      }

      // Run the migration
      final itemsMigrated = await migration.migrate();

      // Mark as completed
      await markCompleted(migration.id);

      debugPrint('[MigrationService] Migration completed: ${migration.id}, items: $itemsMigrated');

      return MigrationResult(
        migrationId: migration.id,
        success: true,
        itemsMigrated: itemsMigrated,
      );
    } catch (e, st) {
      debugPrint('[MigrationService] Migration failed: ${migration.id}, error: $e');
      debugPrint('$st');

      return MigrationResult(
        migrationId: migration.id,
        success: false,
        itemsMigrated: 0,
        error: e.toString(),
      );
    }
  }

  /// Force re-run a migration (even if already completed)
  Future<MigrationResult> forceRunMigration(Migration migration) async {
    // Remove from completed list first
    final prefs = await SharedPreferences.getInstance();
    final completed = await getCompletedMigrations();
    completed.remove(migration.id);
    await prefs.setStringList(_migrationsKey, completed.toList());

    // Now run it
    return runMigration(migration);
  }
}

// ============================================================
// Concrete Migrations
// ============================================================

/// Migration: Convert journal frontmatter from `assets:` to `entries:` format
///
/// Old format:
/// ```yaml
/// assets:
///   abc123: Daily/assets/2025-12-17_15-09.wav
/// ```
///
/// New format:
/// ```yaml
/// entries:
///   abc123:
///     type: voice
///     audioPath: Daily/assets/2025-12-17_15-09.wav
///     status: complete
/// ```
class AssetsToEntriesMigration extends Migration {
  final FileSystemService _fileSystemService;

  AssetsToEntriesMigration(this._fileSystemService);

  @override
  String get id => 'v1_assets_to_entries';

  @override
  String get description => 'Convert journal frontmatter from assets: to entries: format';

  @override
  Future<bool> canRun() async {
    // Check if any journal files have the old assets: format
    try {
      final vaultPath = await _fileSystemService.getRootPath();
      final journalFolder = _fileSystemService.getJournalFolderName();
      final journalsPath = '$vaultPath/$journalFolder';

      final dir = Directory(journalsPath);
      if (!await dir.exists()) return false;

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          final content = await entity.readAsString();
          if (_hasOldAssetsFormat(content)) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      debugPrint('[AssetsToEntriesMigration] canRun error: $e');
      return false;
    }
  }

  bool _hasOldAssetsFormat(String content) {
    // Check if file has assets: (regardless of whether entries: exists)
    // We'll merge assets into entries if both exist
    final hasAssets = RegExp(r'^assets:', multiLine: true).hasMatch(content);
    // Also check for incorrect audioPath key that needs fixing
    final hasIncorrectKey = content.contains('audioPath:');
    return hasAssets || hasIncorrectKey;
  }

  @override
  Future<int> migrate() async {
    int migratedCount = 0;

    try {
      final vaultPath = await _fileSystemService.getRootPath();
      final journalFolder = _fileSystemService.getJournalFolderName();
      final journalsPath = '$vaultPath/$journalFolder';

      final dir = Directory(journalsPath);
      if (!await dir.exists()) return 0;

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          final content = await entity.readAsString();

          if (_hasOldAssetsFormat(content)) {
            final newContent = _migrateContent(content);
            if (newContent != content) {
              await entity.writeAsString(newContent);
              migratedCount++;
              debugPrint('[AssetsToEntriesMigration] Migrated: ${entity.path}');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AssetsToEntriesMigration] Error during migration: $e');
      rethrow;
    }

    return migratedCount;
  }

  String _migrateContent(String content) {
    // Split frontmatter and body
    final trimmed = content.trim();
    if (!trimmed.startsWith('---')) return content;

    final endIndex = trimmed.indexOf('---', 3);
    if (endIndex == -1) return content;

    final frontmatter = trimmed.substring(3, endIndex).trim();
    final body = trimmed.substring(endIndex + 3).trim();

    // Parse the frontmatter YAML
    try {
      final yaml = loadYaml(frontmatter);
      if (yaml is! Map) return content;

      final assets = yaml['assets'] as Map?;
      final existingEntries = yaml['entries'] as Map? ?? {};

      // If no assets and no entries, nothing to migrate
      if (assets == null && existingEntries.isEmpty) return content;

      // Build new frontmatter with merged entries: format
      final buffer = StringBuffer();
      buffer.writeln('---');

      // Copy non-assets and non-entries fields
      for (final entry in yaml.entries) {
        if (entry.key != 'assets' && entry.key != 'entries') {
          buffer.writeln('${entry.key}: ${entry.value}');
        }
      }

      // Output merged entries
      buffer.writeln('entries:');

      // First, write existing entries (fix audioPath -> audio if needed)
      for (final entry in existingEntries.entries) {
        final entryId = entry.key.toString();
        final entryData = entry.value;

        buffer.writeln('  $entryId:');
        if (entryData is Map) {
          for (final field in entryData.entries) {
            // Fix incorrect key: audioPath should be audio
            final key = field.key == 'audioPath' ? 'audio' : field.key;
            buffer.writeln('    $key: ${field.value}');
          }
        }
      }

      // Then, convert and add assets (skip if already in entries)
      if (assets != null) {
        for (final entry in assets.entries) {
          final entryId = entry.key.toString();

          // Skip if this asset ID already exists in entries
          if (existingEntries.containsKey(entryId)) {
            debugPrint('[AssetsToEntriesMigration] Skipping $entryId - already in entries');
            continue;
          }

          final audioPath = entry.value.toString();

          buffer.writeln('  $entryId:');
          buffer.writeln('    type: voice');
          buffer.writeln('    audio: $audioPath');
          buffer.writeln('    status: complete');
        }
      }

      buffer.writeln('---');
      buffer.writeln();
      buffer.write(body);

      return buffer.toString();
    } catch (e) {
      debugPrint('[AssetsToEntriesMigration] YAML parse error: $e');
      return content;
    }
  }
}
