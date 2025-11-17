import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

/// GitHub API-based sync service for mobile platforms
///
/// This service uses GitHub's REST API directly instead of Git operations.
/// Designed for platforms where git2dart (libgit2) is not available (Android, iOS).
///
/// Features:
/// - Upload files (create/update) via API
/// - Download files via API
/// - List repository contents
/// - Track file changes via SHA comparison
///
/// Limitations:
/// - Files must be <100MB (GitHub API limit)
/// - No atomic commits (each file is separate API call)
/// - No built-in merge conflict resolution
/// - Rate limited (5000 requests/hour for authenticated users)
///
/// API Documentation: https://docs.github.com/en/rest/repos/contents
class GitHubApiSyncService {
  GitHubApiSyncService._internal();
  static final GitHubApiSyncService instance = GitHubApiSyncService._internal();

  String? _githubToken;
  String? _owner;
  String? _repo;

  /// Set GitHub authentication token and repository info
  void configure({
    required String githubToken,
    required String owner,
    required String repo,
  }) {
    _githubToken = githubToken;
    _owner = owner;
    _repo = repo;
    debugPrint('[GitHubApiSync] Configured for $owner/$repo');
  }

  /// Check if service is configured
  bool get isConfigured =>
      _githubToken != null && _owner != null && _repo != null;

  /// Get file contents from repository as bytes
  ///
  /// Returns the file content as bytes, or null if file doesn't exist
  Future<List<int>?> getFileBytes(String path) async {
    if (!isConfigured) {
      throw StateError('GitHubApiSyncService not configured');
    }

    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/contents/$path',
      );

      debugPrint('[GitHubApiSync] Getting file: $path');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $_githubToken',
          'Accept': 'application/vnd.github.v3+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content = data['content'] as String;

        // Decode Base64 content to bytes
        final bytes = base64.decode(content.replaceAll('\n', ''));

        debugPrint(
          '[GitHubApiSync] ✅ Downloaded file: $path (${bytes.length} bytes)',
        );
        return bytes;
      } else if (response.statusCode == 404) {
        debugPrint('[GitHubApiSync] File not found: $path');
        return null;
      } else {
        debugPrint(
          '[GitHubApiSync] ❌ Error getting file: ${response.statusCode} ${response.body}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('[GitHubApiSync] ❌ Exception getting file: $e');
      return null;
    }
  }

  /// Upload file to repository (create or update) - using bytes
  ///
  /// If file exists, it will be updated. If not, it will be created.
  /// Returns true if successful, false otherwise.
  Future<bool> uploadFileBytes({
    required String path,
    required List<int> bytes,
    String? message,
  }) async {
    if (!isConfigured) {
      throw StateError('GitHubApiSyncService not configured');
    }

    try {
      // First, check if file exists to get its SHA (required for updates)
      String? sha;
      final existingFile = await _getFileMetadata(path);
      if (existingFile != null) {
        sha = existingFile['sha'] as String?;
      }

      final url = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/contents/$path',
      );

      // Encode content as Base64 (already bytes, no UTF-8 encoding needed)
      final encodedContent = base64.encode(bytes);

      final body = {
        'message': message ?? 'Update $path via Parachute',
        'content': encodedContent,
        if (sha != null) 'sha': sha, // Required for updates
      };

      debugPrint(
        '[GitHubApiSync] ${sha != null ? 'Updating' : 'Creating'} file: $path',
      );

      final response = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $_githubToken',
          'Accept': 'application/vnd.github.v3+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('[GitHubApiSync] ✅ Uploaded file: $path');
        return true;
      } else {
        debugPrint(
          '[GitHubApiSync] ❌ Error uploading file: ${response.statusCode} ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('[GitHubApiSync] ❌ Exception uploading file: $e');
      return false;
    }
  }

  /// Delete file from repository
  Future<bool> deleteFile({required String path, String? message}) async {
    if (!isConfigured) {
      throw StateError('GitHubApiSyncService not configured');
    }

    try {
      // Get file SHA (required for deletion)
      final existingFile = await _getFileMetadata(path);
      if (existingFile == null) {
        debugPrint('[GitHubApiSync] File not found for deletion: $path');
        return false;
      }

      final sha = existingFile['sha'] as String;

      final url = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/contents/$path',
      );

      final body = {
        'message': message ?? 'Delete $path via Parachute',
        'sha': sha,
      };

      debugPrint('[GitHubApiSync] Deleting file: $path');

      final response = await http.delete(
        url,
        headers: {
          'Authorization': 'Bearer $_githubToken',
          'Accept': 'application/vnd.github.v3+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        debugPrint('[GitHubApiSync] ✅ Deleted file: $path');
        return true;
      } else {
        debugPrint(
          '[GitHubApiSync] ❌ Error deleting file: ${response.statusCode} ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('[GitHubApiSync] ❌ Exception deleting file: $e');
      return false;
    }
  }

  /// List all files in a directory (recursive)
  ///
  /// Returns a map of file paths to their SHA hashes
  Future<Map<String, String>> listFiles({String path = ''}) async {
    if (!isConfigured) {
      throw StateError('GitHubApiSyncService not configured');
    }

    final files = <String, String>{};

    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/contents/$path',
      );

      debugPrint('[GitHubApiSync] Listing directory: $path');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $_githubToken',
          'Accept': 'application/vnd.github.v3+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> items = jsonDecode(response.body) as List<dynamic>;

        for (final item in items) {
          final itemMap = item as Map<String, dynamic>;
          final itemType = itemMap['type'] as String;
          final itemPath = itemMap['path'] as String;
          final itemSha = itemMap['sha'] as String;

          if (itemType == 'file') {
            files[itemPath] = itemSha;
          } else if (itemType == 'dir') {
            // Recursively list subdirectory
            final subFiles = await listFiles(path: itemPath);
            files.addAll(subFiles);
          }
        }

        debugPrint('[GitHubApiSync] ✅ Found ${files.length} files in $path');
      } else if (response.statusCode == 404) {
        debugPrint('[GitHubApiSync] Directory not found: $path');
      } else {
        debugPrint(
          '[GitHubApiSync] ❌ Error listing directory: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[GitHubApiSync] ❌ Exception listing directory: $e');
    }

    return files;
  }

  /// Get file metadata (SHA, size, etc.) without downloading content
  Future<Map<String, dynamic>?> _getFileMetadata(String path) async {
    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/contents/$path',
      );

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $_githubToken',
          'Accept': 'application/vnd.github.v3+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        debugPrint(
          '[GitHubApiSync] ❌ Error getting metadata: ${response.statusCode}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('[GitHubApiSync] ❌ Exception getting metadata: $e');
      return null;
    }
  }

  /// Calculate SHA hash for local file content (to compare with remote)
  String calculateSHA(String content) {
    // GitHub uses Git's blob SHA-1 format: "blob <size>\0<content>"
    final bytes = utf8.encode(content);
    final header = utf8.encode('blob ${bytes.length}\u0000');
    final fullContent = [...header, ...bytes];
    final digest = sha1.convert(fullContent);
    return digest.toString();
  }

  /// Sync local directory with remote repository
  ///
  /// This is a simple implementation that:
  /// 1. Lists all remote files
  /// 2. Lists all local files
  /// 3. Uploads new/modified local files
  /// 4. Downloads new/modified remote files
  /// 5. Deletes remote files that don't exist locally
  ///
  /// Note: This does NOT handle conflicts! Last write wins.
  Future<SyncResult> sync({
    required String localPath,
    required String remotePath,
  }) async {
    if (!isConfigured) {
      throw StateError('GitHubApiSyncService not configured');
    }

    debugPrint('[GitHubApiSync] Starting sync: $localPath <-> $remotePath');

    final result = SyncResult();

    try {
      // List remote files
      final remoteFiles = await listFiles(path: remotePath);
      debugPrint('[GitHubApiSync] Remote files: ${remoteFiles.length}');

      // List local files
      final localFiles = await _listLocalFiles(localPath);
      debugPrint('[GitHubApiSync] Local files: ${localFiles.length}');

      // Upload new/modified local files
      for (final localEntry in localFiles.entries) {
        final relativePath = localEntry.key;
        final localSha = localEntry.value;
        final fullRemotePath = p.join(remotePath, relativePath);

        final remoteSha = remoteFiles[fullRemotePath];

        if (remoteSha == null) {
          // File doesn't exist remotely - upload it
          debugPrint('[GitHubApiSync] Uploading new file: $relativePath');
          final localFile = File(p.join(localPath, relativePath));
          final bytes = await localFile.readAsBytes();

          if (await uploadFileBytes(
            path: fullRemotePath,
            bytes: bytes,
            message: 'Add $relativePath via Parachute mobile',
          )) {
            result.uploaded++;
          }
        } else if (remoteSha != localSha) {
          // File exists but content differs - upload it
          debugPrint('[GitHubApiSync] Uploading modified file: $relativePath');
          final localFile = File(p.join(localPath, relativePath));
          final bytes = await localFile.readAsBytes();

          if (await uploadFileBytes(
            path: fullRemotePath,
            bytes: bytes,
            message: 'Update $relativePath via Parachute mobile',
          )) {
            result.uploaded++;
          }
        }
      }

      // Download new/modified remote files
      for (final remoteEntry in remoteFiles.entries) {
        final fullRemotePath = remoteEntry.key;
        final remoteSha = remoteEntry.value;

        // Get relative path by removing remotePath prefix
        final relativePath = fullRemotePath.startsWith(remotePath)
            ? fullRemotePath.substring(remotePath.length + 1)
            : fullRemotePath;

        final localSha = localFiles[relativePath];

        if (localSha == null) {
          // File doesn't exist locally - download it
          debugPrint('[GitHubApiSync] Downloading new file: $relativePath');
          final bytes = await getFileBytes(fullRemotePath);

          if (bytes != null) {
            final localFile = File(p.join(localPath, relativePath));
            await localFile.parent.create(recursive: true);
            await localFile.writeAsBytes(bytes);
            result.downloaded++;
          }
        } else if (localSha != remoteSha) {
          // File exists but content differs - download it
          debugPrint(
            '[GitHubApiSync] Downloading modified file: $relativePath',
          );
          final bytes = await getFileBytes(fullRemotePath);

          if (bytes != null) {
            final localFile = File(p.join(localPath, relativePath));
            await localFile.writeAsBytes(bytes);
            result.downloaded++;
          }
        }
      }

      // Delete remote files that don't exist locally
      for (final remoteEntry in remoteFiles.entries) {
        final fullRemotePath = remoteEntry.key;
        final relativePath = fullRemotePath.startsWith(remotePath)
            ? fullRemotePath.substring(remotePath.length + 1)
            : fullRemotePath;

        if (!localFiles.containsKey(relativePath)) {
          debugPrint('[GitHubApiSync] Deleting remote file: $relativePath');
          if (await deleteFile(
            path: fullRemotePath,
            message: 'Delete $relativePath via Parachute mobile',
          )) {
            result.deleted++;
          }
        }
      }

      debugPrint(
        '[GitHubApiSync] ✅ Sync complete: ${result.uploaded} uploaded, ${result.downloaded} downloaded, ${result.deleted} deleted',
      );
    } catch (e) {
      debugPrint('[GitHubApiSync] ❌ Sync error: $e');
      result.error = e.toString();
    }

    return result;
  }

  /// Check if a file is binary based on extension
  bool _isBinaryFile(String path) {
    final ext = p.extension(path).toLowerCase();
    const binaryExtensions = {
      '.wav',
      '.mp3',
      '.m4a',
      '.ogg',
      '.flac',
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.pdf',
      '.zip',
      '.tar',
      '.gz',
    };
    return binaryExtensions.contains(ext);
  }

  /// List all files in local directory with their SHA hashes
  Future<Map<String, String>> _listLocalFiles(String path) async {
    final files = <String, String>{};
    final dir = Directory(path);

    if (!await dir.exists()) {
      return files;
    }

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        // Get relative path
        final relativePath = p.relative(entity.path, from: path);

        // Skip .git folder (Git's internal files should never be synced via API)
        if (relativePath.startsWith('.git${p.separator}') ||
            relativePath == '.git') {
          continue;
        }

        // Calculate SHA based on file type
        final bytes = await entity.readAsBytes();
        final sha = calculateSHAFromBytes(bytes);

        files[relativePath] = sha;
      }
    }

    return files;
  }

  /// Calculate SHA hash from bytes (for binary files)
  String calculateSHAFromBytes(List<int> bytes) {
    // GitHub uses Git's blob SHA-1 format: "blob <size>\0<content>"
    final header = utf8.encode('blob ${bytes.length}\u0000');
    final fullContent = [...header, ...bytes];
    final digest = sha1.convert(fullContent);
    return digest.toString();
  }
}

/// Result of a sync operation
class SyncResult {
  int uploaded = 0;
  int downloaded = 0;
  int deleted = 0;
  String? error;

  bool get hasChanges => uploaded > 0 || downloaded > 0 || deleted > 0;
  bool get isSuccess => error == null;
}
