import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/space.dart';
import './space_storage_provider.dart';
import '../../../core/services/git/git_service.dart';
import '../../../core/services/file_system_service.dart';

// Space List Provider - Now uses local storage
final spaceListProvider = FutureProvider<List<Space>>((ref) async {
  final storageService = ref.watch(spaceStorageServiceProvider);
  return storageService.listSpaces();
});

// Selected Space Provider
final selectedSpaceProvider = StateProvider<Space?>((ref) => null);

// Space Actions Provider
final spaceActionsProvider = Provider((ref) => SpaceActions(ref));

class SpaceActions {
  final Ref ref;

  SpaceActions(this.ref);

  Future<Space> createSpace({
    required String name,
    String? icon,
    String? color,
  }) async {
    final storageService = ref.read(spaceStorageServiceProvider);
    final space = await storageService.createSpace(
      name: name,
      icon: icon,
      color: color,
    );

    // Trigger Git auto-commit
    await _commitSpaceChange('Create space: $name');

    // Refresh the space list
    ref.invalidate(spaceListProvider);

    return space;
  }

  Future<Space> updateSpace({
    required String id,
    String? name,
    String? icon,
    String? color,
  }) async {
    final storageService = ref.read(spaceStorageServiceProvider);
    final space = await storageService.updateSpace(
      id: id,
      name: name,
      icon: icon,
      color: color,
    );

    // Trigger Git auto-commit
    await _commitSpaceChange('Update space: ${space.name}');

    // Refresh the space list
    ref.invalidate(spaceListProvider);

    return space;
  }

  Future<void> deleteSpace(String id) async {
    final storageService = ref.read(spaceStorageServiceProvider);

    // Get space name before deletion for commit message
    final space = await storageService.getSpace(id);
    final spaceName = space?.name ?? id;

    await storageService.deleteSpace(id);

    // Trigger Git auto-commit
    await _commitSpaceChange('Delete space: $spaceName');

    // Clear selection if the deleted space was selected
    final selectedSpace = ref.read(selectedSpaceProvider);
    if (selectedSpace?.id == id) {
      ref.read(selectedSpaceProvider.notifier).state = null;
    }

    // Refresh the space list
    ref.invalidate(spaceListProvider);
  }

  void selectSpace(Space space) {
    ref.read(selectedSpaceProvider.notifier).state = space;
  }

  /// Helper to commit space changes to Git
  Future<void> _commitSpaceChange(String message) async {
    try {
      final gitService = GitService.instance;
      final fileSystemService = FileSystemService();
      final vaultPath = await fileSystemService.getRootPath();

      // Check if Git is initialized
      final isGitRepo = await gitService.isGitRepository(vaultPath);
      if (!isGitRepo) return;

      // Open repository
      final repo = await gitService.openRepository(vaultPath);
      if (repo == null) return;

      // Stage all changes
      await gitService.addAll(repo: repo);

      // Commit changes
      await gitService.commit(
        repo: repo,
        message: message,
        authorName: 'Parachute',
        authorEmail: 'parachute@local',
      );
    } catch (e) {
      // Don't fail the operation if Git commit fails
      print('[SpaceActions] Git commit failed: $e');
    }
  }
}
