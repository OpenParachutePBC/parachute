import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/services/github/github_oauth_service.dart';
import 'package:app/core/services/github/github_api_service.dart';
import 'package:app/features/recorder/services/storage_service.dart';
import 'package:app/features/recorder/providers/service_providers.dart';

/// GitHub authentication state
class GitHubAuthState {
  final bool isAuthenticated;
  final bool isAuthenticating;
  final String? accessToken; // User access token (for API calls)
  final String?
  installationToken; // Installation access token (for Git operations, repository-scoped)
  final int? installationId; // GitHub App installation ID
  final GitHubUser? user;
  final String? error;

  GitHubAuthState({
    this.isAuthenticated = false,
    this.isAuthenticating = false,
    this.accessToken,
    this.installationToken,
    this.installationId,
    this.user,
    this.error,
  });

  GitHubAuthState copyWith({
    bool? isAuthenticated,
    bool? isAuthenticating,
    String? accessToken,
    String? installationToken,
    int? installationId,
    GitHubUser? user,
    String? error,
  }) {
    return GitHubAuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      accessToken: accessToken ?? this.accessToken,
      installationToken: installationToken ?? this.installationToken,
      installationId: installationId ?? this.installationId,
      user: user ?? this.user,
      error: error,
    );
  }
}

/// GitHub authentication provider
class GitHubAuthNotifier extends StateNotifier<GitHubAuthState> {
  final StorageService _storageService;
  final GitHubOAuthService _oauthService = GitHubOAuthService.instance;
  final GitHubAPIService _apiService = GitHubAPIService.instance;

  GitHubAuthNotifier(this._storageService) : super(GitHubAuthState()) {
    _loadSavedAuth();
  }

  /// Load saved authentication from storage
  Future<void> _loadSavedAuth() async {
    try {
      final token = await _storageService.getGitHubToken();

      if (token != null && token.isNotEmpty) {
        debugPrint('[GitHubAuth] Found saved token, loading user info...');

        // Set token in API service
        _apiService.setAccessToken(token);

        // Fetch user info to verify token is still valid
        final user = await _apiService.getAuthenticatedUser();

        if (user != null) {
          // Get installation ID (for GitHub Apps)
          final installationId = await _oauthService.getUserInstallationId(
            token,
          );

          state = state.copyWith(
            isAuthenticated: true,
            accessToken: token,
            installationToken: token,
            installationId: installationId,
            user: user,
          );
          debugPrint('[GitHubAuth] ✅ Authenticated as ${user.login}');
          if (installationId != null) {
            debugPrint(
              '[GitHubAuth] ✅ Installation ID restored: $installationId',
            );
          }
        } else {
          // Token invalid, clear it
          debugPrint('[GitHubAuth] ⚠️  Saved token is invalid, clearing');
          await signOut();
        }
      }
    } catch (e) {
      debugPrint('[GitHubAuth] ❌ Error loading saved auth: $e');
    }
  }

  /// Start GitHub OAuth flow
  Future<bool> signIn() async {
    try {
      state = state.copyWith(isAuthenticating: true, error: null);
      debugPrint('[GitHubAuth] Starting sign-in flow...');

      // Start OAuth flow
      final authResult = await _oauthService.authorize();

      if (authResult == null) {
        state = state.copyWith(
          isAuthenticating: false,
          error: 'Failed to authorize with GitHub',
        );
        return false;
      }

      final accessToken = authResult['access_token'];
      if (accessToken == null) {
        state = state.copyWith(
          isAuthenticating: false,
          error: 'No access token received',
        );
        return false;
      }

      // Set token in API service
      _apiService.setAccessToken(accessToken);

      // Get user information
      final user = await _apiService.getAuthenticatedUser();

      if (user == null) {
        state = state.copyWith(
          isAuthenticating: false,
          error: 'Failed to get user information',
        );
        return false;
      }

      // Get installation ID (which repositories user authorized)
      debugPrint('[GitHubAuth] Getting installation ID...');
      final installationId = await _oauthService.getUserInstallationId(
        accessToken,
      );

      if (installationId == null) {
        // App not installed - need to redirect user to installation page
        final appSlug = _oauthService.appSlug;
        if (appSlug.isNotEmpty) {
          state = state.copyWith(
            isAuthenticating: false,
            error:
                'GitHub App not installed. Click below to install and select repositories.',
          );
          // Open installation URL
          debugPrint('[GitHubAuth] Opening installation URL...');
          await _oauthService.openInstallationPage();
        } else {
          state = state.copyWith(
            isAuthenticating: false,
            error:
                'GitHub App not installed. Please install it at https://github.com/settings/installations',
          );
        }
        return false;
      }

      // For GitHub Apps with user-to-server tokens, the user access token itself
      // is already scoped to the repositories the user authorized during installation.
      // We don't need a separate installation token (that requires JWT + private key).
      // The user access token works for both API calls AND Git operations.
      debugPrint(
        '[GitHubAuth] Using user access token (already repository-scoped)',
      );

      // Save user access token to storage (works for both API and Git operations)
      await _storageService.saveGitHubToken(accessToken);

      // Update state
      state = state.copyWith(
        isAuthenticated: true,
        isAuthenticating: false,
        accessToken: accessToken, // User token for API calls AND Git operations
        installationToken:
            accessToken, // Same token (already repository-scoped)
        installationId: installationId,
        user: user,
        error: null,
      );

      debugPrint('[GitHubAuth] ✅ Successfully signed in as ${user.login}');
      debugPrint('[GitHubAuth] ✅ Installation ID: $installationId');
      debugPrint(
        '[GitHubAuth] ✅ Installation token obtained (repository-scoped)',
      );
      return true;
    } catch (e) {
      debugPrint('[GitHubAuth] ❌ Error during sign-in: $e');
      state = state.copyWith(isAuthenticating: false, error: e.toString());
      return false;
    }
  }

  /// Sign out and clear stored credentials
  Future<void> signOut() async {
    try {
      debugPrint('[GitHubAuth] Signing out...');

      // Clear token from storage
      await _storageService.deleteGitHubToken();

      // Clear token from API service
      _apiService.clearAccessToken();

      // Reset state
      state = GitHubAuthState();

      debugPrint('[GitHubAuth] ✅ Signed out successfully');
    } catch (e) {
      debugPrint('[GitHubAuth] ❌ Error during sign-out: $e');
    }
  }

  /// Refresh user information
  Future<void> refreshUser() async {
    try {
      if (state.accessToken == null) {
        debugPrint('[GitHubAuth] ⚠️  No access token, cannot refresh user');
        return;
      }

      debugPrint('[GitHubAuth] Refreshing user info...');

      _apiService.setAccessToken(state.accessToken!);
      final user = await _apiService.getAuthenticatedUser();

      if (user != null) {
        state = state.copyWith(user: user);
        debugPrint('[GitHubAuth] ✅ User info refreshed');
      } else {
        debugPrint(
          '[GitHubAuth] ⚠️  Failed to refresh user, token may be invalid',
        );
        await signOut();
      }
    } catch (e) {
      debugPrint('[GitHubAuth] ❌ Error refreshing user: $e');
    }
  }

  @override
  void dispose() {
    _oauthService.dispose();
    super.dispose();
  }
}

/// Provider for GitHub authentication
final gitHubAuthProvider =
    StateNotifierProvider<GitHubAuthNotifier, GitHubAuthState>((ref) {
      final storageService = ref.watch(storageServiceProvider);
      return GitHubAuthNotifier(storageService);
    });
