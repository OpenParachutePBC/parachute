import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:git2dart/git2dart.dart';
import 'package:path/path.dart' as p;

/// Git service for managing local Git repositories
///
/// Proof-of-concept implementation using git2dart (libgit2 bindings)
///
/// This service wraps git2dart operations for:
/// - Repository initialization
/// - Adding files to staging
/// - Committing changes
/// - Future: push/pull, authentication, conflict resolution
class GitService {
  GitService._internal();
  static final GitService instance = GitService._internal();

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

      debugPrint('[GitService] ✅ Repository initialized successfully');
      return repo;
    } catch (e) {
      debugPrint('[GitService] ❌ Error initializing repository: $e');
      return null;
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
      debugPrint('[GitService] ❌ Error opening repository: $e');
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
      // status is a getter property, not a method
      final statusMap = repo.status;

      final modified = <String>[];
      final added = <String>[];
      final deleted = <String>[];
      final untracked = <String>[];

      statusMap.forEach((path, statusSet) {
        if (statusSet.contains(GitStatus.wtModified)) {
          modified.add(path);
        }
        if (statusSet.contains(GitStatus.wtNew)) {
          untracked.add(path);
        }
        if (statusSet.contains(GitStatus.indexNew)) {
          added.add(path);
        }
        if (statusSet.contains(GitStatus.wtDeleted)) {
          deleted.add(path);
        }
      });

      return {
        'modified': modified,
        'added': added,
        'deleted': deleted,
        'untracked': untracked,
        'untrackedCount': untracked.length,
        'clean': statusMap.isEmpty,
      };
    } catch (e) {
      debugPrint('[GitService] ❌ Error getting status: $e');
      return {'error': e.toString()};
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
}
