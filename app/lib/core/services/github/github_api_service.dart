import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Model for GitHub repository
class GitHubRepository {
  final int id;
  final String name;
  final String fullName;
  final String? description;
  final bool private;
  final String htmlUrl;
  final String cloneUrl;
  final String defaultBranch;
  final DateTime createdAt;
  final DateTime updatedAt;

  GitHubRepository({
    required this.id,
    required this.name,
    required this.fullName,
    this.description,
    required this.private,
    required this.htmlUrl,
    required this.cloneUrl,
    required this.defaultBranch,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GitHubRepository.fromJson(Map<String, dynamic> json) {
    return GitHubRepository(
      id: json['id'] as int,
      name: json['name'] as String,
      fullName: json['full_name'] as String,
      description: json['description'] as String?,
      private: json['private'] as bool,
      htmlUrl: json['html_url'] as String,
      cloneUrl: json['clone_url'] as String,
      defaultBranch: json['default_branch'] as String? ?? 'main',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Model for GitHub user
class GitHubUser {
  final int id;
  final String login;
  final String? name;
  final String? email;
  final String avatarUrl;
  final String htmlUrl;

  GitHubUser({
    required this.id,
    required this.login,
    this.name,
    this.email,
    required this.avatarUrl,
    required this.htmlUrl,
  });

  factory GitHubUser.fromJson(Map<String, dynamic> json) {
    return GitHubUser(
      id: json['id'] as int,
      login: json['login'] as String,
      name: json['name'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatar_url'] as String,
      htmlUrl: json['html_url'] as String,
    );
  }
}

/// GitHub API service for managing repositories
///
/// This service provides methods to interact with the GitHub API:
/// - Get authenticated user information
/// - List user repositories
/// - Create new repositories
/// - Get repository details
class GitHubAPIService {
  GitHubAPIService._internal();
  static final GitHubAPIService instance = GitHubAPIService._internal();

  static const String _apiBaseUrl = 'https://api.github.com';
  String? _accessToken;

  /// Set the OAuth access token for API requests
  void setAccessToken(String token) {
    _accessToken = token;
    debugPrint('[GitHubAPI] Access token set');
  }

  /// Clear the access token
  void clearAccessToken() {
    _accessToken = null;
    debugPrint('[GitHubAPI] Access token cleared');
  }

  /// Get common headers for API requests
  Map<String, String> _getHeaders() {
    return {
      'Accept': 'application/vnd.github+json',
      'Authorization': 'Bearer $_accessToken',
      'X-GitHub-Api-Version': '2022-11-28',
    };
  }

  /// Verify if a token is valid
  /// Returns true if token is valid, false if it returns 401 (invalid/expired)
  Future<bool> verifyToken(String token) async {
    try {
      debugPrint('[GitHubAPI] Verifying token...');

      final response = await http.get(
        Uri.parse('$_apiBaseUrl/user'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $token',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );

      if (response.statusCode == 200) {
        debugPrint('[GitHubAPI] ✅ Token is valid');
        return true;
      } else if (response.statusCode == 401) {
        debugPrint('[GitHubAPI] ❌ Token is invalid (401)');
        debugPrint('[GitHubAPI] Response: ${response.body}');
        return false;
      } else {
        debugPrint('[GitHubAPI] ⚠️  Unexpected status: ${response.statusCode}');
        // For other errors, assume token might be valid (could be rate limit, etc.)
        return true;
      }
    } catch (e) {
      debugPrint('[GitHubAPI] ❌ Error verifying token: $e');
      // Network error - can't verify, so return true (optimistic)
      throw e;
    }
  }

  /// Get authenticated user information
  Future<GitHubUser?> getAuthenticatedUser() async {
    if (_accessToken == null) {
      debugPrint('[GitHubAPI] ❌ No access token set');
      return null;
    }

    try {
      debugPrint('[GitHubAPI] Fetching authenticated user...');

      final response = await http.get(
        Uri.parse('$_apiBaseUrl/user'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final user = GitHubUser.fromJson(data);

        debugPrint('[GitHubAPI] ✅ Got user: ${user.login}');
        return user;
      } else {
        debugPrint('[GitHubAPI] ❌ Failed to get user: ${response.statusCode}');
        debugPrint('[GitHubAPI] Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[GitHubAPI] ❌ Error getting user: $e');
      return null;
    }
  }

  /// List repositories for the authenticated user
  ///
  /// When using GitHub Apps with installationId, lists ONLY authorized repositories.
  /// This provides repository-specific access control.
  ///
  /// [installationId] - GitHub App installation ID (for repository-scoped access)
  /// [page] - Page number (default: 1)
  /// [perPage] - Results per page (default: 100)
  Future<List<GitHubRepository>> listRepositories({
    int? installationId,
    int page = 1,
    int perPage = 100,
  }) async {
    if (_accessToken == null) {
      debugPrint('[GitHubAPI] ❌ No access token set');
      return [];
    }

    try {
      String endpoint;
      if (installationId != null) {
        // GitHub App: List only authorized repositories
        endpoint =
            '$_apiBaseUrl/user/installations/$installationId/repositories';
        debugPrint('[GitHubAPI] Listing GitHub App authorized repositories');
      } else {
        // OAuth App fallback: List all user repositories
        endpoint = '$_apiBaseUrl/user/repos';
        debugPrint('[GitHubAPI] Listing all user repositories');
      }

      final uri = Uri.parse(endpoint).replace(
        queryParameters: {
          'page': page.toString(),
          'per_page': perPage.toString(),
        },
      );

      final response = await http.get(uri, headers: _getHeaders());

      if (response.statusCode == 200) {
        List<dynamic> repoList;

        if (installationId != null) {
          // GitHub App installation API returns: { "total_count": X, "repositories": [...] }
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          repoList = data['repositories'] as List<dynamic>;
          final totalCount = data['total_count'];
          debugPrint('[GitHubAPI] Total authorized: $totalCount');
        } else {
          // User repos API returns array directly: [...]
          repoList = jsonDecode(response.body) as List<dynamic>;
        }

        final repos = repoList
            .map(
              (json) => GitHubRepository.fromJson(json as Map<String, dynamic>),
            )
            .toList();

        debugPrint('[GitHubAPI] ✅ Found ${repos.length} repositories');
        if (installationId != null) {
          debugPrint(
            '[GitHubAPI] ℹ️  Repository-scoped access: These are the ONLY repos you authorized',
          );
        }
        return repos;
      } else {
        debugPrint(
          '[GitHubAPI] ❌ Failed to list repos: ${response.statusCode}',
        );
        debugPrint('[GitHubAPI] Response: ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('[GitHubAPI] ❌ Error listing repositories: $e');
      return [];
    }
  }

  /// Create a new repository
  ///
  /// [name] - Repository name (required)
  /// [description] - Repository description (optional)
  /// [private] - Whether the repo should be private (default: true)
  /// [autoInit] - Initialize with README (default: true)
  Future<GitHubRepository?> createRepository({
    required String name,
    String? description,
    bool private = true,
    bool autoInit = true,
  }) async {
    if (_accessToken == null) {
      debugPrint('[GitHubAPI] ❌ No access token set');
      return null;
    }

    try {
      debugPrint('[GitHubAPI] Creating repository: $name');

      final response = await http.post(
        Uri.parse('$_apiBaseUrl/user/repos'),
        headers: _getHeaders(),
        body: jsonEncode({
          'name': name,
          'description':
              description ??
              'Parachute vault - Personal knowledge base with voice recordings and AI spaces',
          'private': private,
          'auto_init': autoInit, // Creates initial README.md
          'has_issues': false,
          'has_projects': false,
          'has_wiki': false,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final repo = GitHubRepository.fromJson(data);

        debugPrint('[GitHubAPI] ✅ Repository created: ${repo.fullName}');
        return repo;
      } else {
        debugPrint(
          '[GitHubAPI] ❌ Failed to create repo: ${response.statusCode}',
        );
        debugPrint('[GitHubAPI] Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[GitHubAPI] ❌ Error creating repository: $e');
      return null;
    }
  }

  /// Get a specific repository by owner and name
  ///
  /// [owner] - Repository owner (username)
  /// [repo] - Repository name
  Future<GitHubRepository?> getRepository({
    required String owner,
    required String repo,
  }) async {
    if (_accessToken == null) {
      debugPrint('[GitHubAPI] ❌ No access token set');
      return null;
    }

    try {
      debugPrint('[GitHubAPI] Getting repository: $owner/$repo');

      final response = await http.get(
        Uri.parse('$_apiBaseUrl/repos/$owner/$repo'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final repository = GitHubRepository.fromJson(data);

        debugPrint('[GitHubAPI] ✅ Got repository: ${repository.fullName}');
        return repository;
      } else {
        debugPrint('[GitHubAPI] ❌ Failed to get repo: ${response.statusCode}');
        debugPrint('[GitHubAPI] Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[GitHubAPI] ❌ Error getting repository: $e');
      return null;
    }
  }

  /// Search repositories (useful for finding existing Parachute vaults)
  ///
  /// [query] - Search query
  /// [page] - Page number (default: 1)
  /// [perPage] - Results per page (default: 30, max: 100)
  Future<List<GitHubRepository>> searchRepositories({
    required String query,
    int page = 1,
    int perPage = 30,
  }) async {
    if (_accessToken == null) {
      debugPrint('[GitHubAPI] ❌ No access token set');
      return [];
    }

    try {
      debugPrint('[GitHubAPI] Searching repositories: $query');

      final uri = Uri.parse('$_apiBaseUrl/search/repositories').replace(
        queryParameters: {
          'q': '$query user:@me', // Search only user's repos
          'page': page.toString(),
          'per_page': perPage.toString(),
          'sort': 'updated',
        },
      );

      final response = await http.get(uri, headers: _getHeaders());

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = data['items'] as List<dynamic>;
        final repos = items
            .map(
              (json) => GitHubRepository.fromJson(json as Map<String, dynamic>),
            )
            .toList();

        debugPrint('[GitHubAPI] ✅ Found ${repos.length} repositories');
        return repos;
      } else {
        debugPrint(
          '[GitHubAPI] ❌ Failed to search repos: ${response.statusCode}',
        );
        debugPrint('[GitHubAPI] Response: ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('[GitHubAPI] ❌ Error searching repositories: $e');
      return [];
    }
  }
}
