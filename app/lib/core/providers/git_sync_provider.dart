import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:git2dart/git2dart.dart';

import 'package:app/core/services/git/git_service.dart';
import 'package:app/features/files/providers/local_file_browser_provider.dart';
import 'package:app/features/recorder/providers/service_providers.dart';

/// Git sync state
class GitSyncState {
  final bool isEnabled;
  final String? repositoryUrl;
  final String? currentBranch;
  final bool hasRemote;
  final bool isSyncing;
  final String? lastError;
  final DateTime? lastSyncTime;
  final int filesUploading; // Number of files being pushed
  final int filesDownloading; // Number of files being pulled

  const GitSyncState({
    this.isEnabled = false,
    this.repositoryUrl,
    this.currentBranch,
    this.hasRemote = false,
    this.isSyncing = false,
    this.lastError,
    this.lastSyncTime,
    this.filesUploading = 0,
    this.filesDownloading = 0,
  });

  GitSyncState copyWith({
    bool? isEnabled,
    String? repositoryUrl,
    String? currentBranch,
    bool? hasRemote,
    bool? isSyncing,
    String? lastError,
    DateTime? lastSyncTime,
    int? filesUploading,
    int? filesDownloading,
  }) {
    return GitSyncState(
      isEnabled: isEnabled ?? this.isEnabled,
      repositoryUrl: repositoryUrl ?? this.repositoryUrl,
      currentBranch: currentBranch ?? this.currentBranch,
      hasRemote: hasRemote ?? this.hasRemote,
      isSyncing: isSyncing ?? this.isSyncing,
      lastError: lastError,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      filesUploading: filesUploading ?? this.filesUploading,
      filesDownloading: filesDownloading ?? this.filesDownloading,
    );
  }
}

/// Git sync notifier
class GitSyncNotifier extends StateNotifier<GitSyncState> {
  GitSyncNotifier(this._ref) : super(const GitSyncState());

  final Ref _ref;
  final GitService _gitService = GitService.instance;
  Repository? _repository;
  Timer? _periodicSyncTimer;

  /// Initialize Git sync by checking if vault is a Git repository
  /// and restoring saved settings
  Future<void> initialize() async {
    final fileSystemService = _ref.read(fileSystemServiceProvider);
    final vaultPath = await fileSystemService.getRootPath();
    final isGitRepo = await _gitService.isGitRepository(vaultPath);

    if (isGitRepo) {
      _repository = await _gitService.openRepository(vaultPath);
      if (_repository != null) {
        await _updateStatus();

        // Try to restore Git sync settings from storage
        await _restoreSettings();
      }
    }
  }

  /// Restore Git sync settings from secure storage
  Future<void> _restoreSettings() async {
    try {
      // Import StorageService to check saved settings
      final storageService = _ref.read(storageServiceProvider);

      final isEnabled = await storageService.isGitSyncEnabled();
      final repoUrl = await storageService.getGitHubRepositoryUrl();
      final token = await storageService.getGitHubToken();

      if (isEnabled && repoUrl != null && token != null) {
        debugPrint('[GitSync] Restoring Git sync settings from storage');

        // Set the token
        _gitService.setGitHubToken(token);

        // Update state
        await _updateStatus();
        state = state.copyWith(isEnabled: true, repositoryUrl: repoUrl);

        // Enable periodic sync
        enablePeriodicSync();

        debugPrint('[GitSync] ✅ Git sync restored and enabled');
      }
    } catch (e) {
      debugPrint('[GitSync] Error restoring settings: $e');
    }
  }

  /// Setup Git sync with a GitHub repository
  Future<bool> setupGitSync({
    required String repositoryUrl,
    required String githubToken,
  }) async {
    try {
      state = state.copyWith(isSyncing: true, lastError: null);

      // Set GitHub token
      _gitService.setGitHubToken(githubToken);

      final fileSystemService = _ref.read(fileSystemServiceProvider);
      final vaultPath = await fileSystemService.getRootPath();
      final isGitRepo = await _gitService.isGitRepository(vaultPath);

      if (!isGitRepo) {
        // Initialize git repo in existing vault directory
        debugPrint('[GitSync] Initializing git repository in: $vaultPath');
        _repository = await _gitService.initializeRepository(vaultPath);

        if (_repository == null) {
          state = state.copyWith(
            isSyncing: false,
            lastError: 'Failed to initialize repository',
          );
          return false;
        }

        // Add remote
        debugPrint('[GitSync] Adding remote: $repositoryUrl');
        final remoteAdded = await _gitService.addRemote(
          repo: _repository!,
          name: 'origin',
          url: repositoryUrl,
        );

        if (!remoteAdded) {
          state = state.copyWith(
            isSyncing: false,
            lastError: 'Failed to add remote',
          );
          return false;
        }

        // Check if we have any commits locally
        final hasCommits = await _gitService.hasCommits(repo: _repository!);

        if (!hasCommits) {
          // No commits yet - create initial commit with existing files
          debugPrint('[GitSync] No commits found, creating initial commit...');

          // Add all existing files
          debugPrint('[GitSync] Adding all files to index...');
          final addedAll = await _gitService.addAll(repo: _repository!);

          if (!addedAll) {
            debugPrint('[GitSync] Warning: Failed to add files to index');
          }

          // Create initial commit
          debugPrint('[GitSync] Creating initial commit...');
          final commitSha = await _gitService.commit(
            repo: _repository!,
            message: 'Initial commit - Parachute vault setup',
            authorName: 'Parachute',
            authorEmail: 'parachute@local',
          );

          if (commitSha == null) {
            debugPrint(
              '[GitSync] ⚠️  Warning: Failed to create initial commit',
            );
          } else {
            debugPrint('[GitSync] ✅ Initial commit created: $commitSha');
          }
        }

        // Get current branch name
        final currentBranch = _gitService.getCurrentBranch(repo: _repository!);
        final branchName = currentBranch ?? 'main';
        debugPrint('[GitSync] Using branch: $branchName');

        // Try to pull from remote (in case repo already has content)
        debugPrint('[GitSync] Pulling from remote...');
        final pulled = await _gitService.pull(
          repo: _repository!,
          branchName: branchName,
        );

        if (!pulled) {
          debugPrint(
            '[GitSync] Pull failed (remote might be empty), will push local commits...',
          );
        }

        // Push to remote
        debugPrint('[GitSync] Pushing to remote...');
        final pushed = await _gitService.push(
          repo: _repository!,
          branchName: branchName,
        );

        if (pushed) {
          debugPrint('[GitSync] ✅ Successfully pushed to remote');
        } else {
          debugPrint('[GitSync] ⚠️  Warning: Failed to push to remote');
        }
      } else {
        // Open existing repository
        _repository = await _gitService.openRepository(vaultPath);
      }

      await _updateStatus();
      state = state.copyWith(
        isEnabled: true,
        repositoryUrl: repositoryUrl,
        isSyncing: false,
        lastSyncTime: DateTime.now(),
      );

      // Enable periodic background sync (every 5 minutes)
      enablePeriodicSync();

      return true;
    } catch (e) {
      state = state.copyWith(isSyncing: false, lastError: e.toString());
      return false;
    }
  }

  /// Push local changes to remote
  Future<bool> push() async {
    if (_repository == null) return false;

    try {
      state = state.copyWith(isSyncing: true, lastError: null);

      final success = await _gitService.push(repo: _repository!);

      if (success) {
        await _updateStatus();
        state = state.copyWith(isSyncing: false, lastSyncTime: DateTime.now());
      } else {
        state = state.copyWith(isSyncing: false, lastError: 'Push failed');
      }

      return success;
    } catch (e) {
      state = state.copyWith(isSyncing: false, lastError: e.toString());
      return false;
    }
  }

  /// Pull changes from remote
  Future<bool> pull() async {
    if (_repository == null) return false;

    try {
      state = state.copyWith(isSyncing: true, lastError: null);

      final success = await _gitService.pull(repo: _repository!);

      if (success) {
        await _updateStatus();
        state = state.copyWith(isSyncing: false, lastSyncTime: DateTime.now());
      } else {
        state = state.copyWith(isSyncing: false, lastError: 'Pull failed');
      }

      return success;
    } catch (e) {
      state = state.copyWith(isSyncing: false, lastError: e.toString());
      return false;
    }
  }

  /// Sync (pull then push)
  Future<bool> sync() async {
    debugPrint('[GitSync] 🔄 sync() called');

    if (_repository == null) {
      debugPrint('[GitSync] ❌ No repository available');
      return false;
    }

    try {
      debugPrint('[GitSync] Setting isSyncing=true...');
      state = state.copyWith(isSyncing: true, lastError: null);
      debugPrint('[GitSync] State updated: isSyncing=${state.isSyncing}');

      // Check if we have any commits locally
      final hasCommits = await _gitService.hasCommits(repo: _repository!);

      if (!hasCommits) {
        // No commits yet - create initial commit with existing files
        debugPrint('[GitSync] No commits found, creating initial commit...');

        // Add all existing files
        final addedAll = await _gitService.addAll(repo: _repository!);
        if (!addedAll) {
          debugPrint('[GitSync] Warning: Failed to add files to index');
        }

        // Create initial commit
        final commitSha = await _gitService.commit(
          repo: _repository!,
          message: 'Initial commit - Parachute vault setup',
          authorName: 'Parachute',
          authorEmail: 'parachute@local',
        );

        if (commitSha != null) {
          debugPrint('[GitSync] ✅ Initial commit created: $commitSha');
        }
      } else {
        // We have commits - check for new/modified files and commit them
        final status = await _gitService.getStatus(_repository!);
        final untrackedFiles = status['untracked'] as List;
        final modifiedFiles = status['modified'] as List;
        final deletedFiles = status['deleted'] as List;
        final hasChanges =
            untrackedFiles.isNotEmpty ||
            modifiedFiles.isNotEmpty ||
            deletedFiles.isNotEmpty;

        if (hasChanges) {
          final totalChanges =
              untrackedFiles.length +
              modifiedFiles.length +
              deletedFiles.length;
          debugPrint(
            '[GitSync] Changes detected ($totalChanges files), committing...',
          );

          // Update state to show files being uploaded
          state = state.copyWith(filesUploading: totalChanges);

          // Add all files to staging
          final addedAll = await _gitService.addAll(repo: _repository!);
          if (!addedAll) {
            debugPrint('[GitSync] ⚠️  Warning: Failed to add files to index');
          }

          // Commit changes
          final commitSha = await _gitService.commit(
            repo: _repository!,
            message: 'Auto-sync: ${DateTime.now().toIso8601String()}',
            authorName: 'Parachute',
            authorEmail: 'parachute@local',
          );

          if (commitSha != null) {
            debugPrint('[GitSync] ✅ Changes committed: $commitSha');
          } else {
            debugPrint('[GitSync] ⚠️  Warning: Failed to commit changes');
          }
        } else {
          debugPrint('[GitSync] No local changes to commit');
        }
      }

      // Get current branch name
      final currentBranch = _gitService.getCurrentBranch(repo: _repository!);
      final branchName = currentBranch ?? 'main';
      debugPrint('[GitSync] Using branch: $branchName');

      // Try to pull (may fail if remote is empty)
      final pullSuccess = await _gitService.pull(
        repo: _repository!,
        branchName: branchName,
      );
      if (!pullSuccess) {
        debugPrint(
          '[GitSync] Pull failed (remote might be empty), continuing with push...',
        );
      }

      // Always push, even if pull failed
      final pushSuccess = await _gitService.push(
        repo: _repository!,
        branchName: branchName,
      );
      if (!pushSuccess) {
        state = state.copyWith(
          isSyncing: false,
          lastError: 'Push failed during sync',
        );
        return false;
      }

      await _updateStatus();
      state = state.copyWith(
        isSyncing: false,
        lastSyncTime: DateTime.now(),
        filesUploading: 0,
        filesDownloading: 0,
      );

      return true;
    } catch (e) {
      state = state.copyWith(isSyncing: false, lastError: e.toString());
      return false;
    }
  }

  /// Enable periodic background sync (every 5 minutes)
  void enablePeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (state.isEnabled && !state.isSyncing) {
        debugPrint('[GitSync] Periodic sync triggered');
        await sync();
      }
    });
  }

  /// Disable periodic sync
  void disablePeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  /// Disable Git sync
  Future<void> disable() async {
    disablePeriodicSync();
    _gitService.clearGitHubToken();
    _repository = null;
    state = const GitSyncState();
  }

  @override
  void dispose() {
    _periodicSyncTimer?.cancel();
    super.dispose();
  }

  /// Update sync status from repository
  Future<void> _updateStatus() async {
    if (_repository == null) return;

    final status = await _gitService.getSyncStatus(_repository!);

    state = state.copyWith(
      hasRemote: status['hasRemote'] as bool,
      currentBranch: status['currentBranch'] as String?,
    );
  }
}

/// Git sync provider
final gitSyncProvider = StateNotifierProvider<GitSyncNotifier, GitSyncState>((
  ref,
) {
  final notifier = GitSyncNotifier(ref);
  // Auto-initialize on first access to restore saved settings
  notifier.initialize();
  return notifier;
});
