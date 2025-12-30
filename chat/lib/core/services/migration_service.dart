import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/file_system_service.dart';

/// Base class for data migrations.
///
/// Extend this class to create new migrations. Each migration should:
/// 1. Have a unique [id] (e.g., 'v1_session_format_update')
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

/// Service for managing and running data migrations in Parachute Chat.
///
/// Usage:
/// ```dart
/// final migrationService = MigrationService(fileSystemService);
/// final results = await migrationService.runPendingMigrations();
/// ```
class MigrationService {
  static const String _migrationsKey = 'chat_completed_migrations';

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
// Chat-specific migrations can be added here
// ============================================================

// Example migration template:
//
// class SessionFormatMigration extends Migration {
//   final FileSystemService _fileSystemService;
//
//   SessionFormatMigration(this._fileSystemService);
//
//   @override
//   String get id => 'v1_session_format';
//
//   @override
//   String get description => 'Update session format';
//
//   @override
//   Future<int> migrate() async {
//     // Migration logic here
//     return 0;
//   }
// }
