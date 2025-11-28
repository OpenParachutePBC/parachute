import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;

import 'package:app/core/services/git/git_service.dart';
import 'package:app/core/services/audio_compression_service_dart.dart';
import 'package:app/features/files/providers/local_file_browser_provider.dart';
import 'package:app/features/recorder/providers/service_providers.dart';

/// Git sync state
class GitSyncState {
  final bool isInitializing; // True while initialize() is running
  final bool isInitialized; // True after initialize() completes
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
    this.isInitializing = false,
    this.isInitialized = false,
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
    bool? isInitializing,
    bool? isInitialized,
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
      isInitializing: isInitializing ?? this.isInitializing,
      isInitialized: isInitialized ?? this.isInitialized,
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
  final AudioCompressionServiceDart _audioCompression =
      AudioCompressionServiceDart();
  Repository? _repository;
  Timer? _periodicSyncTimer;
  Completer<void>? _initCompleter;

  /// Wait for initialization to complete
  /// Useful for code that needs to ensure Git is initialized before operating
  /// Throws if initialization fails
  Future<void> ensureInitialized() async {
    if (state.isInitialized) return;
    // If already initializing, wait for it
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }
    // Otherwise trigger initialization (may throw if it fails)
    await initialize();
  }

  /// Initialize Git sync by checking if vault is a Git repository
  /// and restoring saved settings
  Future<void> initialize() async {
    // Prevent multiple concurrent initializations
    if (state.isInitialized) {
      debugPrint('[GitSync] Already initialized, skipping');
      return;
    }

    // If already initializing, wait for that to complete
    if (_initCompleter != null) {
      debugPrint('[GitSync] Already initializing, waiting...');
      await _initCompleter!.future;
      return;
    }

    _initCompleter = Completer<void>();
    state = state.copyWith(isInitializing: true);
    debugPrint('[GitSync] 🚀 Initializing Git sync...');

    try {
      final fileSystemService = _ref.read(fileSystemServiceProvider);
      final vaultPath = await fileSystemService.getRootPath();
      debugPrint('[GitSync] Vault path: $vaultPath');

      final isGitRepo = await _gitService.isGitRepository(vaultPath);
      debugPrint('[GitSync] Is Git repository: $isGitRepo');

      if (isGitRepo) {
        _repository = await _gitService.openRepository(vaultPath);
        debugPrint('[GitSync] Repository opened: ${_repository != null}');

        if (_repository != null) {
          await _updateStatus();

          // Try to restore Git sync settings from storage
          await _restoreSettings();
        } else {
          debugPrint('[GitSync] ❌ Failed to open repository');
        }
      } else {
        debugPrint('[GitSync] ℹ️  Not a Git repository yet');
      }

      debugPrint('[GitSync] 🚀 Initialization complete');
      state = state.copyWith(isInitializing: false, isInitialized: true);
      _initCompleter!.complete();
    } catch (e) {
      debugPrint('[GitSync] ❌ Initialization failed: $e');
      // Keep isInitialized: false on error so callers know initialization failed
      // Set isInitializing: false so we can retry
      state = state.copyWith(isInitializing: false, isInitialized: false, lastError: e.toString());
      _initCompleter!.completeError(e);
      _initCompleter = null; // Allow retry on failure
    }
  }

  /// Restore Git sync settings from secure storage
  Future<void> _restoreSettings() async {
    try {
      // Import StorageService to check saved settings
      final storageService = _ref.read(storageServiceProvider);

      final isEnabled = await storageService.isGitSyncEnabled();
      var repoUrl = await storageService.getGitHubRepositoryUrl();
      final token = await storageService.getGitHubToken();

      debugPrint('[GitSync] Restore check:');
      debugPrint('  - isEnabled: $isEnabled');
      debugPrint('  - repoUrl: $repoUrl');
      debugPrint('  - hasToken: ${token != null}');

      // Recovery: If we have a token and git repo with remote, but settings aren't saved
      // This can happen if the app was interrupted during setup
      if (token != null && _repository != null && !isEnabled) {
        debugPrint(
          '[GitSync] 🔧 Recovery mode: Found token and repo but sync not enabled',
        );

        // Try to get remote URL from git if not in storage
        if (repoUrl == null) {
          try {
            final status = await _gitService.getSyncStatus(_repository!);
            repoUrl = status['remoteUrl'] as String?;
            if (repoUrl != null) {
              debugPrint(
                '[GitSync] 📡 Retrieved repo URL from git remote: $repoUrl',
              );
              await storageService.saveGitHubRepositoryUrl(repoUrl);
            }
          } catch (e) {
            debugPrint('[GitSync] Could not get remote URL: $e');
          }
        }

        // If we have everything now, enable sync
        if (repoUrl != null) {
          await storageService.setGitSyncEnabled(true);
          debugPrint('[GitSync] ✅ Recovered and enabled Git sync');
        }
      }

      if ((isEnabled || token != null) && repoUrl != null && token != null) {
        debugPrint('[GitSync] Restoring Git sync settings from storage');

        // Set the token
        _gitService.setGitHubToken(token);

        // Update state
        await _updateStatus();
        state = state.copyWith(isEnabled: true, repositoryUrl: repoUrl);

        // Enable periodic sync
        enablePeriodicSync();

        debugPrint('[GitSync] ✅ Git sync restored and enabled');
      } else {
        debugPrint(
          '[GitSync] ℹ️  Git sync not fully configured, skipping restore',
        );
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

        // Add remote (ensure HTTPS format for token authentication)
        final httpsUrl = _ensureHttpsUrl(repositoryUrl);
        debugPrint('[GitSync] Adding remote: $httpsUrl');
        final remoteAdded = await _gitService.addRemote(
          repo: _repository!,
          name: 'origin',
          url: httpsUrl,
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

      // Save settings to persistent storage so they survive app restart
      final storageService = _ref.read(storageServiceProvider);
      await storageService.setGitSyncEnabled(true);
      await storageService.saveGitHubRepositoryUrl(repositoryUrl);
      await storageService.saveGitHubToken(githubToken);

      debugPrint('[GitSync] ✅ Saved Git sync settings to persistent storage');

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

  /// Clean up orphaned temp WAV files
  /// These are temp recording files (with numeric IDs) that don't have corresponding .md files
  /// Returns the number of files cleaned up
  Future<int> _cleanupOrphanedTempFiles() async {
    try {
      final fileSystemService = _ref.read(fileSystemServiceProvider);
      final capturesPath = await fileSystemService.getCapturesPath();
      final capturesDir = Directory(capturesPath);

      if (!await capturesDir.exists()) {
        return 0;
      }

      int cleanedCount = 0;
      final orphanedFiles = <File>[];

      // Find temp WAV files (format: 2025-11-25-1764132350130.wav - with numeric ID)
      // These are different from saved recordings (format: 2025-11-25_11-30-20.wav - with time)
      final tempFilePattern = RegExp(r'^\d{4}-\d{2}-\d{2}-\d+\.(wav|opus)$');

      await for (final entity in capturesDir.list()) {
        if (entity is File) {
          final basename = p.basename(entity.path);
          if (tempFilePattern.hasMatch(basename)) {
            // This is a temp file - check if there's a corresponding .md file
            // Temp files won't have .md files with the same name pattern
            final timestamp = basename.replaceAll(RegExp(r'\.(wav|opus)$'), '');
            final mdPath = p.join(capturesPath, '$timestamp.md');

            if (!await File(mdPath).exists()) {
              orphanedFiles.add(entity);
            }
          }
        }
      }

      if (orphanedFiles.isEmpty) {
        debugPrint('[GitSync] No orphaned temp files to clean up');
        return 0;
      }

      debugPrint('[GitSync] Found ${orphanedFiles.length} orphaned temp files to clean up');

      // Delete orphaned files
      for (final file in orphanedFiles) {
        try {
          final basename = p.basename(file.path);
          await file.delete();
          debugPrint('[GitSync] Deleted orphaned file: $basename');
          cleanedCount++;
        } catch (e) {
          debugPrint('[GitSync] ⚠️  Failed to delete ${p.basename(file.path)}: $e');
        }
      }

      if (cleanedCount > 0) {
        debugPrint('[GitSync] ✅ Cleaned up $cleanedCount orphaned temp files');
      }

      return cleanedCount;
    } catch (e) {
      debugPrint('[GitSync] ❌ Error cleaning up orphaned files: $e');
      return 0;
    }
  }

  /// Convert any WAV files to Opus before syncing
  /// Only converts WAV files that don't already have a corresponding .opus file
  /// Returns the number of files converted
  Future<int> _convertWavToOpus() async {
    try {
      // Skip conversion if Opus library isn't available (e.g., macOS without libopus)
      if (!AudioCompressionServiceDart.isOpusInitialized) {
        debugPrint('[GitSync] ⚠️  Opus not initialized, skipping WAV→Opus conversion');
        debugPrint('[GitSync] ℹ️  WAV files will be synced as-is');
        return 0;
      }

      final fileSystemService = _ref.read(fileSystemServiceProvider);
      final capturesPath = await fileSystemService.getCapturesPath();
      final capturesDir = Directory(capturesPath);

      if (!await capturesDir.exists()) {
        return 0;
      }

      int convertedCount = 0;
      final wavFilesToConvert = <File>[];

      // Find WAV files that need conversion:
      // - Must have a corresponding .md file (real recording, not temp file)
      // - Must NOT already have a corresponding .opus file (skip already converted)
      await for (final entity in capturesDir.list()) {
        if (entity is File && entity.path.endsWith('.wav')) {
          final wavBasename = p.basename(entity.path);
          final timestamp = wavBasename.replaceAll('.wav', '');
          final mdPath = p.join(capturesPath, '$timestamp.md');
          final opusPath = entity.path.replaceAll('.wav', '.opus');

          // Check if it's a real recording (has .md file)
          if (!await File(mdPath).exists()) {
            // Skip temp files - they'll be cleaned up by _cleanupOrphanedTempFiles
            continue;
          }

          // Check if already converted (has .opus file)
          if (await File(opusPath).exists()) {
            // Already has opus, skip
            continue;
          }

          wavFilesToConvert.add(entity);
        }
      }

      if (wavFilesToConvert.isEmpty) {
        debugPrint('[GitSync] No WAV files need conversion (all already have .opus)');
        return 0;
      }

      debugPrint('[GitSync] Found ${wavFilesToConvert.length} WAV files to convert');

      // Convert each WAV file to Opus
      for (final wavFile in wavFilesToConvert) {
        try {
          final wavBasename = p.basename(wavFile.path);
          debugPrint('[GitSync] Converting: $wavBasename');

          await _audioCompression.compressToOpus(
            wavPath: wavFile.path,
            deleteOriginal: false, // Keep WAV for playback and local use
          );

          convertedCount++;
        } catch (e) {
          debugPrint(
            '[GitSync] ⚠️  Failed to convert ${p.basename(wavFile.path)}: $e',
          );
          // Continue with other files even if one fails
        }
      }

      if (convertedCount > 0) {
        debugPrint('[GitSync] ✅ Converted $convertedCount WAV files to Opus');
      }

      return convertedCount;
    } catch (e) {
      debugPrint('[GitSync] ❌ Error converting WAV files: $e');
      return 0;
    }
  }

  /// Sync (pull then push)
  Future<bool> sync() async {
    debugPrint('[GitSync] 🔄 ============================================');
    debugPrint('[GitSync] 🔄 sync() called');
    debugPrint(
      '[GitSync] 🔄 Repository: ${_repository != null ? "✅ Available" : "❌ NULL"}',
    );
    debugPrint(
      '[GitSync] 🔄 State: isEnabled=${state.isEnabled}, repoUrl=${state.repositoryUrl}',
    );
    debugPrint('[GitSync] 🔄 ============================================');

    if (_repository == null) {
      debugPrint('[GitSync] ❌ No repository available - aborting sync');
      return false;
    }

    try {
      state = state.copyWith(isSyncing: true, lastError: null);
      debugPrint('[GitSync] State updated: isSyncing=true');

      // Note: WAV to Opus conversion happens immediately after transcription
      // (see AudioCompressionServiceDart in simple_recording_screen.dart)
      // WAV files are gitignored, so only .opus and .md files are synced

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
        debugPrint('[GitSync] Checking for local changes...');

        // Reopen repository to ensure we see latest file system changes
        final fileSystemService = _ref.read(fileSystemServiceProvider);
        final vaultPath = await fileSystemService.getRootPath();
        _repository = await _gitService.openRepository(vaultPath);

        // Clean up orphaned temp files first
        final cleanedCount = await _cleanupOrphanedTempFiles();
        if (cleanedCount > 0) {
          debugPrint('[GitSync] ✅ Cleaned up $cleanedCount orphaned temp files');
        }

        // Convert any WAV files that need Opus versions
        final convertedCount = await _convertWavToOpus();
        if (convertedCount > 0) {
          debugPrint('[GitSync] ✅ Converted $convertedCount WAV files to Opus');
        }

        // Check git status for changes
        final status = await _gitService.getStatus(_repository!);

        final untrackedFiles = status['untracked'] as List? ?? [];
        final modifiedFiles = status['modified'] as List? ?? [];
        final deletedFiles = status['deleted'] as List? ?? [];

        debugPrint('[GitSync] Status result:');
        debugPrint('  - Untracked: ${untrackedFiles.length}');
        debugPrint('  - Modified: ${modifiedFiles.length}');
        debugPrint('  - Deleted: ${deletedFiles.length}');

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
            '[GitSync] ✅ Changes detected ($totalChanges files), committing...',
          );

          // Update state to show files being uploaded
          state = state.copyWith(filesUploading: totalChanges);

          // Add all files to staging
          debugPrint('[GitSync] Staging all changes...');
          final addedAll = await _gitService.addAll(repo: _repository!);
          if (!addedAll) {
            debugPrint('[GitSync] ❌ Failed to add files to index');
            state = state.copyWith(
              isSyncing: false,
              lastError: 'Failed to stage files',
              filesUploading: 0,
            );
            return false;
          }
          debugPrint('[GitSync] ✅ Files staged successfully');

          // Commit changes
          debugPrint('[GitSync] Creating commit...');
          final commitSha = await _gitService.commit(
            repo: _repository!,
            message: 'Auto-sync: ${DateTime.now().toIso8601String()}',
            authorName: 'Parachute',
            authorEmail: 'parachute@local',
          );

          if (commitSha != null) {
            debugPrint('[GitSync] ✅ Changes committed: $commitSha');
          } else {
            debugPrint('[GitSync] ❌ Failed to commit changes');
            state = state.copyWith(
              isSyncing: false,
              lastError: 'Failed to commit changes',
              filesUploading: 0,
            );
            return false;
          }
        } else {
          debugPrint('[GitSync] ℹ️  No local changes to commit');
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

  /// Convert SSH URLs to HTTPS format for token authentication
  String _ensureHttpsUrl(String url) {
    // Convert git@github.com:user/repo.git to https://github.com/user/repo.git
    if (url.startsWith('git@github.com:')) {
      final path = url.replaceFirst('git@github.com:', '');
      return 'https://github.com/$path';
    }
    // Already HTTPS or other format
    return url;
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
