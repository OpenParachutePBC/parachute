import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;

/// Git service for managing local Git repositories
///
/// Implementation using git2dart (libgit2 bindings)
///
/// This service wraps git2dart operations for:
/// - Repository initialization
/// - Adding files to staging
/// - Committing changes
/// - GitHub integration (clone, push, pull)
/// - Authentication with Personal Access Tokens
class GitService {
  GitService._internal();
  static final GitService instance = GitService._internal();

  /// GitHub Personal Access Token for authentication
  String? _githubToken;

  /// Check if a directory is a Git repository
  Future<bool> isGitRepository(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return false;

      // Check if .git folder exists
      final gitDir = Directory(p.join(path, '.git'));
      return await gitDir.exists();
    } catch (e) {
      debugPrint('[GitService] Error checking if directory is Git repo: $e');
      return false;
    }
  }

  /// Initialize a new Git repository
  Future<Repository?> initRepository(String path) async {
    try {
      debugPrint('[GitService] Initializing Git repository at: $path');

      // Ensure directory exists
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Initialize repository (bare parameter instead of isBare)
      final repo = Repository.init(path: path, bare: false);

      // Ensure .gitignore exists and excludes WAV files
      await ensureGitignore(path);

      debugPrint('[GitService] ✅ Repository initialized successfully');
      return repo;
    } catch (e) {
      debugPrint('[GitService] ❌ Error initializing repository: $e');
      return null;
    }
  }

  /// Ensure .gitignore exists and includes WAV files
  Future<void> ensureGitignore(String repoPath) async {
    try {
      final gitignorePath = p.join(repoPath, '.gitignore');
      final gitignoreFile = File(gitignorePath);

      if (!await gitignoreFile.exists()) {
        // Create new .gitignore with WAV exclusion
        debugPrint('[GitService] Creating .gitignore with WAV exclusion');
        await gitignoreFile.writeAsString('*.wav\n');
      } else {
        // Check if .gitignore already excludes WAV files
        final content = await gitignoreFile.readAsString();
        if (!content.contains('*.wav')) {
          // Append WAV exclusion
          debugPrint('[GitService] Adding *.wav to existing .gitignore');
          await gitignoreFile.writeAsString(
            '$content${content.endsWith('\n') ? '' : '\n'}*.wav\n',
          );
        } else {
          debugPrint('[GitService] .gitignore already excludes WAV files');
        }
      }
    } catch (e) {
      debugPrint('[GitService] ⚠️  Error managing .gitignore: $e');
    }
  }

  /// Open an existing Git repository
  Future<Repository?> openRepository(String path) async {
    try {
      debugPrint('[GitService] Opening Git repository at: $path');

      if (!await isGitRepository(path)) {
        debugPrint('[GitService] ❌ Not a Git repository: $path');
        return null;
      }

      final repo = Repository.open(path);

      debugPrint('[GitService] ✅ Repository opened successfully');
      return repo;
    } catch (e) {
      // On Android, ownership errors are expected due to storage permissions
      if (Platform.isAndroid &&
          e.toString().contains('not owned by current user')) {
        debugPrint('[GitService] ⚠️  Git ownership check failed on Android');
        debugPrint(
          '[GitService] This is a known limitation - libgit2 needs to be built with ownership checks disabled',
        );
        debugPrint('[GitService] Falling back to API sync...');
      } else {
        debugPrint('[GitService] ❌ Error opening repository: $e');
      }
      return null;
    }
  }

  /// Add a file to the staging area
  Future<bool> addFile(Repository repo, String relativePath) async {
    try {
      debugPrint('[GitService] Adding file to staging: $relativePath');

      final index = repo.index;
      // Use add() method which accepts String or IndexEntry
      index.add(relativePath);
      index.write();

      debugPrint('[GitService] ✅ File added to staging');
      return true;
    } catch (e) {
      debugPrint('[GitService] ❌ Error adding file: $e');
      return false;
    }
  }

  /// Add all files to the staging area (git add .)
  /// This includes new files, modifications, AND deletions
  Future<bool> addAll({required Repository repo}) async {
    try {
      debugPrint(
        '[GitService] Adding all files to staging (including deletions)...',
      );

      final index = repo.index;

      // Add all new and modified files (equivalent to git add .)
      index.addAll(['.']);

      // Update all files to detect deletions (equivalent to git add -u)
      // This ensures deleted files are staged for removal
      index.updateAll(['.']);

      index.write();

      debugPrint(
        '[GitService] ✅ All files added to staging (including deletions)',
      );
      return true;
    } catch (e) {
      debugPrint('[GitService] ❌ Error adding all files: $e');
      return false;
    }
  }

  /// Commit staged changes
  Future<String?> commit({
    required Repository repo,
    required String message,
    required String authorName,
    required String authorEmail,
  }) async {
    try {
      debugPrint('[GitService] Creating commit: $message');

      // Create signature
      final signature = Signature.create(
        name: authorName,
        email: authorEmail,
        time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      // Write tree from index
      final index = repo.index;
      final treeOid = index.writeTree();
      final tree = Tree.lookup(repo: repo, oid: treeOid);

      // Get parent commits (if exists)
      final parents = <Commit>[];
      try {
        final headRef = repo.head;
        final headCommit = Commit.lookup(repo: repo, oid: headRef.target);
        parents.add(headCommit);
      } catch (e) {
        // No parent (first commit)
        debugPrint('[GitService] First commit (no parent)');
      }

      // Create commit using Commit.create static method
      final commitOid = Commit.create(
        repo: repo,
        updateRef: 'HEAD',
        author: signature,
        committer: signature,
        message: message,
        tree: tree,
        parents: parents,
      );

      final commitSha = commitOid.sha;
      debugPrint('[GitService] ✅ Commit created: $commitSha');
      return commitSha;
    } catch (e) {
      debugPrint('[GitService] ❌ Error creating commit: $e');
      return null;
    }
  }

  /// Get repository status
  Future<Map<String, dynamic>> getStatus(Repository repo) async {
    try {
      debugPrint('[GitService] 🔍 Getting repository status...');

      // Read the index to ensure it's up to date with the working directory
      final index = repo.index;
      index.read(force: true);

      // WORKAROUND: git2dart's status getter doesn't detect untracked files by default
      // Use addAll + updateAll to detect what would be staged (untracked + modified)
      // Then restore index to original state

      // Save current index state (list of paths)
      final originalIndexPaths = <String>{};
      for (var i = 0; i < index.length; i++) {
        originalIndexPaths.add(index[i].path);
      }
      debugPrint('[GitService] Original index has ${originalIndexPaths.length} entries');

      // Stage everything (this will add untracked files to index)
      index.addAll(['.']);
      index.updateAll(['.']);
      index.write();

      // Now check what's in the index
      final stagedPaths = <String>{};
      for (var i = 0; i < index.length; i++) {
        stagedPaths.add(index[i].path);
      }
      debugPrint('[GitService] After addAll, index has ${stagedPaths.length} entries');

      // Untracked files = files now in index that weren't before
      final untracked = stagedPaths.difference(originalIndexPaths).toList();
      debugPrint('[GitService] Found ${untracked.length} untracked files');

      // Restore index to original state by removing newly added files
      for (final path in untracked) {
        try {
          index.remove(path);
        } catch (e) {
          debugPrint('[GitService] ⚠️  Failed to unstage $path: $e');
        }
      }
      index.write();

      // Now get the actual status for modified/deleted files
      final statusMap = repo.status;

      debugPrint('[GitService] Status map size: ${statusMap.length}');
      debugPrint('[GitService] Status map entries:');
      statusMap.forEach((path, statusSet) {
        debugPrint('  - $path: $statusSet');
      });

      final modified = <String>[];
      final added = <String>[];
      final deleted = <String>[];

      statusMap.forEach((path, statusSet) {
        if (statusSet.contains(GitStatus.wtModified)) {
          modified.add(path);
        }
        if (statusSet.contains(GitStatus.indexNew)) {
          added.add(path);
        }
        if (statusSet.contains(GitStatus.wtDeleted)) {
          deleted.add(path);
        }
      });

      debugPrint('[GitService] Parsed status:');
      debugPrint('  - Modified: ${modified.length}');
      debugPrint('  - Untracked: ${untracked.length}');
      debugPrint('  - Added: ${added.length}');
      debugPrint('  - Deleted: ${deleted.length}');

      return {
        'modified': modified,
        'added': added,
        'deleted': deleted,
        'untracked': untracked,
        'untrackedCount': untracked.length,
        'clean': statusMap.isEmpty && untracked.isEmpty,
      };
    } catch (e) {
      debugPrint('[GitService] ❌ Error getting status: $e');
      return {'error': e.toString()};
    }
  }

  /// Check if repository has any commits
  Future<bool> hasCommits({required Repository repo}) async {
    try {
      // Try to get HEAD reference - if it exists, there are commits
      repo.head;
      debugPrint('[GitService] Repository has commits');
      return true;
    } catch (e) {
      // If HEAD doesn't exist, there are no commits
      debugPrint('[GitService] No commits found: $e');
      return false;
    }
  }

  /// Get current branch name
  String? getCurrentBranch({required Repository repo}) {
    try {
      final head = repo.head;
      // head.name returns something like "refs/heads/main"
      // Extract just the branch name
      final branchName = head.name.replaceFirst('refs/heads/', '');
      debugPrint('[GitService] Current branch: $branchName');
      return branchName;
    } catch (e) {
      debugPrint('[GitService] ❌ Error getting current branch: $e');
      return null;
    }
  }

  /// Get commit history (last N commits)
  Future<List<Map<String, dynamic>>> getCommitHistory(
    Repository repo, {
    int limit = 10,
  }) async {
    try {
      final walker = RevWalk(repo);

      // Start from HEAD
      final headRef = repo.head;
      walker.push(headRef.target);

      // Walk commits with limit
      final commitList = walker.walk(limit: limit);

      return commitList.map((commit) {
        return {
          'sha': commit.oid.sha,
          'message': commit.message,
          'author': commit.author.name,
          'email': commit.author.email,
          'date': DateTime.fromMillisecondsSinceEpoch(
            commit.author.time * 1000,
          ),
        };
      }).toList();
    } catch (e) {
      debugPrint('[GitService] ❌ Error getting commit history: $e');
      return [];
    }
  }

  /// Test helper: Create a simple workflow (init + add + commit)
  Future<bool> testBasicWorkflow({
    required String repoPath,
    required String testFilePath,
    required String testFileContent,
  }) async {
    try {
      debugPrint('[GitService] Testing basic workflow...');

      // 1. Initialize repository
      final repo = await initRepository(repoPath);
      if (repo == null) {
        debugPrint('[GitService] ❌ Failed to initialize repo');
        return false;
      }

      // 2. Create test file
      final file = File(testFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(testFileContent);
      debugPrint('[GitService] Created test file: $testFilePath');

      // Get relative path from repo root
      final relativePath = p.relative(testFilePath, from: repoPath);

      // 3. Add file to staging
      final added = await addFile(repo, relativePath);
      if (!added) {
        debugPrint('[GitService] ❌ Failed to add file');
        return false;
      }

      // 4. Commit
      final commitSha = await commit(
        repo: repo,
        message: 'Initial commit: Add test file',
        authorName: 'Parachute',
        authorEmail: 'test@parachute.app',
      );

      if (commitSha == null) {
        debugPrint('[GitService] ❌ Failed to create commit');
        return false;
      }

      // 5. Verify commit history
      final history = await getCommitHistory(repo);
      if (history.isEmpty) {
        debugPrint('[GitService] ❌ No commits in history');
        return false;
      }

      debugPrint('[GitService] ✅ Basic workflow test passed!');
      debugPrint('[GitService] Commit SHA: $commitSha');
      debugPrint('[GitService] Commits in history: ${history.length}');

      return true;
    } catch (e) {
      debugPrint('[GitService] ❌ Test failed: $e');
      return false;
    }
  }

  // ============================================================================
  // GitHub Integration
  // ============================================================================

  /// Set GitHub Personal Access Token for authentication
  void setGitHubToken(String token) {
    _githubToken = token;
    debugPrint('[GitService] GitHub token set');
  }

  /// Clear GitHub Personal Access Token
  void clearGitHubToken() {
    _githubToken = null;
    debugPrint('[GitService] GitHub token cleared');
  }

  /// Clone a GitHub repository
  ///
  /// [url] - Repository URL (e.g., "https://github.com/user/repo.git")
  /// [localPath] - Local path where repository will be cloned
  /// [username] - GitHub username (usually "git" or actual username)
  ///
  /// Returns the cloned Repository or null if failed
  Future<Repository?> initializeRepository(String path) async {
    try {
      debugPrint('[GitService] Initializing repository at: $path');

      // Initialize the repository
      final repo = Repository.init(path: path, bare: false);

      debugPrint('[GitService] ✅ Repository initialized successfully');
      return repo;
    } catch (e) {
      debugPrint('[GitService] ❌ Error initializing repository: $e');
      return null;
    }
  }

  /// Clone a repository from a remote URL
  ///
  /// Returns the cloned Repository or null if failed
  Future<Repository?> cloneRepository({
    required String url,
    required String localPath,
    String username = 'git',
  }) async {
    try {
      debugPrint('[GitService] Cloning repository from: $url');
      debugPrint('[GitService] Clone destination: $localPath');

      if (_githubToken == null) {
        debugPrint('[GitService] ❌ No GitHub token set');
        return null;
      }

      // Ensure parent directory exists
      final dir = Directory(localPath);
      if (await dir.exists()) {
        debugPrint('[GitService] ❌ Directory already exists: $localPath');
        return null;
      }

      await dir.parent.create(recursive: true);

      // Create credentials for authentication
      final credentials = UserPass(username: username, password: _githubToken!);

      // Clone repository
      final repo = Repository.clone(
        url: url,
        localPath: localPath,
        bare: false,
        callbacks: Callbacks(credentials: credentials),
      );

      // Ensure .gitignore exists and excludes WAV files
      await ensureGitignore(localPath);

      debugPrint('[GitService] ✅ Repository cloned successfully');
      return repo;
    } catch (e) {
      debugPrint('[GitService] ❌ Error cloning repository: $e');
      return null;
    }
  }

  /// Add a remote to a repository
  ///
  /// [repo] - Repository to add remote to
  /// [name] - Name of the remote (e.g., "origin")
  /// [url] - URL of the remote repository
  ///
  /// Returns true if remote was added successfully
  Future<bool> addRemote({
    required Repository repo,
    required String name,
    required String url,
  }) async {
    try {
      debugPrint('[GitService] Adding remote $name: $url');

      Remote.create(repo: repo, name: name, url: url);

      debugPrint('[GitService] ✅ Remote added successfully');
      return true;
    } catch (e) {
      debugPrint('[GitService] ❌ Error adding remote: $e');
      return false;
    }
  }

  /// Push changes to remote repository
  ///
  /// [repo] - Repository to push from
  /// [remoteName] - Name of remote (default: "origin")
  /// [branchName] - Branch to push (default: "main")
  /// [username] - GitHub username for authentication
  ///
  /// Returns true if push succeeded
  Future<bool> push({
    required Repository repo,
    String remoteName = 'origin',
    String branchName = 'main',
    String username = 'git',
  }) async {
    try {
      debugPrint('[GitService] 🔼 Pushing to $remoteName/$branchName');

      if (_githubToken == null) {
        debugPrint('[GitService] ❌ No GitHub token set');
        return false;
      }

      // Get remote
      final remote = Remote.lookup(repo: repo, name: remoteName);

      // Create credentials for authentication
      final credentials = UserPass(username: username, password: _githubToken!);

      // Push to remote
      remote.push(
        refspecs: ['refs/heads/$branchName:refs/heads/$branchName'],
        callbacks: Callbacks(credentials: credentials),
      );

      debugPrint('[GitService] ✅ Push successful');
      return true;
    } catch (e) {
      debugPrint('[GitService] ❌ Error pushing: $e');
      return false;
    }
  }

  /// Pull changes from remote repository
  ///
  /// [repo] - Repository to pull into
  /// [remoteName] - Name of remote (default: "origin")
  /// [branchName] - Branch to pull (default: "main")
  /// [username] - GitHub username for authentication
  ///
  /// Returns true if pull succeeded
  Future<bool> pull({
    required Repository repo,
    String remoteName = 'origin',
    String branchName = 'main',
    String username = 'git',
  }) async {
    try {
      debugPrint('[GitService] 🔽 Pulling from $remoteName/$branchName');

      if (_githubToken == null) {
        debugPrint('[GitService] ❌ No GitHub token set');
        return false;
      }

      // Get remote
      final remote = Remote.lookup(repo: repo, name: remoteName);

      // Create credentials for authentication
      final credentials = UserPass(username: username, password: _githubToken!);

      // Fetch from remote
      remote.fetch(
        refspecs: [
          'refs/heads/$branchName:refs/remotes/$remoteName/$branchName',
        ],
        callbacks: Callbacks(credentials: credentials),
      );

      // Get remote branch
      final remoteBranch = Branch.lookup(
        repo: repo,
        name: '$remoteName/$branchName',
        type: GitBranch.remote,
      );

      // Get current HEAD to check if we need to merge
      final headRef = repo.head;
      final headCommit = Commit.lookup(repo: repo, oid: headRef.target);

      // Check if remote is ahead of local
      if (headCommit.oid.sha == remoteBranch.target.sha) {
        debugPrint('[GitService] Already up to date');
        return true;
      }

      // Create annotated commit for merge
      final annotatedCommit = AnnotatedCommit.lookup(
        repo: repo,
        oid: remoteBranch.target,
      );

      // Perform merge (this sets up the merge state)
      Merge.commit(repo: repo, commit: annotatedCommit);

      // Check if there are conflicts
      final index = repo.index;
      if (index.hasConflicts) {
        debugPrint('[GitService] ❌ Merge conflicts detected');
        // For now, abort the merge
        repo.stateCleanup();
        return false;
      }

      // Write the merged index to a tree
      final treeOid = index.writeTree();
      final tree = Tree.lookup(repo: repo, oid: treeOid);

      // Create signature
      final signature = Signature.create(
        name: 'Parachute',
        email: 'parachute@local',
        time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      // Get the remote commit
      final remoteCommit = Commit.lookup(repo: repo, oid: remoteBranch.target);

      // Create merge commit with both parents
      final mergeCommitOid = Commit.create(
        repo: repo,
        updateRef: 'HEAD',
        author: signature,
        committer: signature,
        message: 'Merge remote-tracking branch \'$remoteName/$branchName\'',
        tree: tree,
        parents: [headCommit, remoteCommit],
      );

      // Clean up merge state
      repo.stateCleanup();

      debugPrint(
        '[GitService] ✅ Pull successful with merge commit: ${mergeCommitOid.sha}',
      );
      return true;
    } catch (e) {
      debugPrint('[GitService] ❌ Error pulling: $e');
      // Try to clean up merge state if it was started
      try {
        repo.stateCleanup();
      } catch (_) {}
      return false;
    }
  }

  /// Get current sync status
  ///
  /// Returns a map with sync information:
  /// - hasRemote: bool
  /// - remoteName: String?
  /// - remoteUrl: String?
  /// - currentBranch: String?
  /// - ahead: int (commits ahead of remote)
  /// - behind: int (commits behind remote)
  Future<Map<String, dynamic>> getSyncStatus(Repository repo) async {
    try {
      final status = <String, dynamic>{
        'hasRemote': false,
        'remoteName': null,
        'remoteUrl': null,
        'currentBranch': null,
        'ahead': 0,
        'behind': 0,
      };

      // Get current branch
      try {
        final head = repo.head;
        final branchName = head.name.replaceAll('refs/heads/', '');
        status['currentBranch'] = branchName;
      } catch (e) {
        debugPrint('[GitService] No HEAD found: $e');
      }

      // Check for remotes
      try {
        final remoteNames = repo.remotes;
        if (remoteNames.isNotEmpty) {
          final remoteName = remoteNames.first;
          final remote = Remote.lookup(repo: repo, name: remoteName);
          status['hasRemote'] = true;
          status['remoteName'] = remote.name;
          status['remoteUrl'] = remote.url;
        }
      } catch (e) {
        debugPrint('[GitService] Error getting remotes: $e');
      }

      return status;
    } catch (e) {
      debugPrint('[GitService] ❌ Error getting sync status: $e');
      return {'hasRemote': false, 'error': e.toString()};
    }
  }
}
