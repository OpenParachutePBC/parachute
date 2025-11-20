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
  final bool needsReauth; // Token was revoked/expired, user needs to reconnect

  GitHubAuthState({
    this.isAuthenticated = false,
    this.isAuthenticating = false,
    this.accessToken,
    this.installationToken,
    this.installationId,
    this.user,
    this.error,
    this.needsReauth = false,
  });

  GitHubAuthState copyWith({
    bool? isAuthenticated,
    bool? isAuthenticating,
    String? accessToken,
    String? installationToken,
    int? installationId,
    GitHubUser? user,
    String? error,
    bool? needsReauth,
  }) {
    return GitHubAuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      accessToken: accessToken ?? this.accessToken,
      installationToken: installationToken ?? this.installationToken,
      installationId: installationId ?? this.installationId,
      user: user ?? this.user,
      error: error,
      needsReauth: needsReauth ?? this.needsReauth,
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

  /// Check if access token needs refreshing (within 5 minutes of expiry)
  /// Returns true if token should be refreshed
  Future<bool> _shouldRefreshToken() async {
    final expiresAt = await _storageService.getGitHubTokenExpiresAt();
    if (expiresAt == null) {
      // No expiry time means token expiration is not enabled
      return false;
    }

    final now = DateTime.now();
    final timeUntilExpiry = expiresAt.difference(now);

    // Refresh if token expires in less than 5 minutes
    if (timeUntilExpiry.inMinutes < 5) {
      debugPrint(
        '[GitHubAuth] Token expires in ${timeUntilExpiry.inMinutes} minutes, needs refresh',
      );
      return true;
    }

    return false;
  }

  /// Refresh the access token using the refresh token
  /// Returns true if successful, false otherwise
  Future<bool> _refreshAccessToken() async {
    try {
      final refreshToken = await _storageService.getGitHubRefreshToken();
      if (refreshToken == null) {
        debugPrint('[GitHubAuth] ❌ No refresh token available');
        return false;
      }

      // Check if refresh token itself has expired (6 months)
      final refreshTokenExpiresAt = await _storageService
          .getGitHubRefreshTokenExpiresAt();
      if (refreshTokenExpiresAt != null) {
        final now = DateTime.now();
        if (now.isAfter(refreshTokenExpiresAt)) {
          debugPrint('[GitHubAuth] ❌ Refresh token has expired');
          // Clear everything and require re-authentication
          await _storageService.deleteGitHubToken();
          state = state.copyWith(
            isAuthenticated: false,
            accessToken: null,
            installationToken: null,
            needsReauth: true,
            error:
                'Your GitHub session has expired. Please reconnect to continue syncing.',
          );
          return false;
        }
      }

      debugPrint('[GitHubAuth] 🔄 Refreshing access token...');

      // Call OAuth service to refresh the token
      final result = await _oauthService.refreshAccessToken(refreshToken);

      if (result == null) {
        debugPrint('[GitHubAuth] ❌ Token refresh failed');
        return false;
      }

      // Extract new tokens
      final newAccessToken = result['access_token'] as String;
      final newRefreshToken = result['refresh_token'] as String;
      final expiresIn = result['expires_in'] as int;
      final refreshTokenExpiresIn = result['refresh_token_expires_in'] as int;

      // Save new tokens
      await _storageService.saveGitHubToken(newAccessToken);
      await _storageService.saveGitHubRefreshToken(newRefreshToken);

      // Calculate and save new expiry times
      final now = DateTime.now();
      final accessTokenExpiry = now.add(Duration(seconds: expiresIn));
      final newRefreshTokenExpiry = now.add(
        Duration(seconds: refreshTokenExpiresIn),
      );

      await _storageService.saveGitHubTokenExpiresAt(accessTokenExpiry);
      await _storageService.saveGitHubRefreshTokenExpiresAt(
        newRefreshTokenExpiry,
      );

      // Update API service with new token
      _apiService.setAccessToken(newAccessToken);

      // Update state
      state = state.copyWith(
        accessToken: newAccessToken,
        installationToken: newAccessToken,
      );

      debugPrint('[GitHubAuth] ✅ Access token refreshed successfully');
      debugPrint(
        '[GitHubAuth] New token expires at: ${accessTokenExpiry.toIso8601String()}',
      );

      return true;
    } catch (e) {
      debugPrint('[GitHubAuth] ❌ Error refreshing token: $e');
      return false;
    }
  }

  /// Verify if a token is still valid by making a test API call
  /// Returns true if valid, false if invalid (401 error)
  /// Also attempts to refresh the token if it's about to expire
  Future<bool> _verifyToken(String token) async {
    try {
      // First check if token needs refreshing based on expiry time
      if (await _shouldRefreshToken()) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          return true; // Token was successfully refreshed
        }
        // If refresh failed, continue to verify the current token
      }

      debugPrint('[GitHubAuth] Verifying token validity...');

      // Make a simple API call to check if token works
      final response = await _apiService.verifyToken(token);

      if (response) {
        debugPrint('[GitHubAuth] ✅ Token is valid');
        return true;
      } else {
        debugPrint('[GitHubAuth] ❌ Token is invalid (401)');
        // Token is invalid - try to refresh it
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          debugPrint('[GitHubAuth] ✅ Token refreshed after 401 error');
          return true;
        }
        return false;
      }
    } catch (e) {
      // Network error or other issue - assume token might be valid
      // (optimistic approach for offline scenarios)
      debugPrint('[GitHubAuth] ⚠️  Could not verify token (network issue): $e');
      return true; // Optimistic: assume valid if we can't verify
    }
  }

  /// Load saved authentication from storage
  Future<void> _loadSavedAuth() async {
    try {
      final token = await _storageService.getGitHubToken();

      if (token != null && token.isNotEmpty) {
        debugPrint('[GitHubAuth] Found saved token, loading user info...');

        // Set token in API service
        _apiService.setAccessToken(token);

        // Try to fetch user info to verify token is still valid
        final isTokenValid = await _verifyToken(token);

        if (isTokenValid) {
          // Token is valid - load user info
          try {
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
                needsReauth: false,
              );
              debugPrint('[GitHubAuth] ✅ Authenticated as ${user.login}');
              if (installationId != null) {
                debugPrint(
                  '[GitHubAuth] ✅ Installation ID restored: $installationId',
                );
              }
            }
          } catch (e) {
            debugPrint('[GitHubAuth] ⚠️  Error loading user info: $e');
            // Use optimistic auth if we can't load user info but token is valid
            state = state.copyWith(
              isAuthenticated: true,
              accessToken: token,
              installationToken: token,
              needsReauth: false,
            );
          }
        } else {
          // Token is invalid (401) - it was revoked or the app was uninstalled
          debugPrint(
            '[GitHubAuth] ❌ Token is invalid (revoked or app uninstalled)',
          );
          debugPrint('[GitHubAuth] Clearing stored token...');
          await _storageService.deleteGitHubToken();
          _apiService.clearAccessToken();

          // Set needsReauth flag with helpful error message
          state = state.copyWith(
            isAuthenticated: false,
            accessToken: null,
            installationToken: null,
            installationId: null,
            user: null,
            needsReauth: true,
            error:
                'Your GitHub access has been revoked. Please reconnect to continue syncing.',
          );
        }
      }
    } catch (e) {
      debugPrint('[GitHubAuth] ❌ Error loading saved auth: $e');
    }
  }

  /// Start GitHub OAuth flow
  Future<bool> signIn() async {
    try {
      state = state.copyWith(
        isAuthenticating: true,
        error: null,
        needsReauth: false,
      );
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

      // Get installation ID (check callback first, then API)
      int? installationId;
      final installationIdFromCallback = authResult['installation_id'];
      if (installationIdFromCallback != null) {
        debugPrint(
          '[GitHubAuth] Using installation ID from callback: $installationIdFromCallback',
        );
        installationId = int.tryParse(installationIdFromCallback);
      }

      // If not in callback, query API
      if (installationId == null) {
        debugPrint('[GitHubAuth] Querying installation ID from API...');
        installationId = await _oauthService.getUserInstallationId(accessToken);
      }

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

      // Save refresh token and expiry times if provided (token expiration enabled)
      final refreshToken = authResult['refresh_token'] as String?;
      final expiresIn = authResult['expires_in'] as int?;
      final refreshTokenExpiresIn =
          authResult['refresh_token_expires_in'] as int?;

      if (refreshToken != null && expiresIn != null) {
        debugPrint('[GitHubAuth] ✅ Token expiration enabled');
        debugPrint('[GitHubAuth] Access token expires in: $expiresIn seconds');

        await _storageService.saveGitHubRefreshToken(refreshToken);

        // Calculate expiry times
        final now = DateTime.now();
        final accessTokenExpiry = now.add(Duration(seconds: expiresIn));
        final refreshTokenExpiry = refreshTokenExpiresIn != null
            ? now.add(Duration(seconds: refreshTokenExpiresIn))
            : now.add(const Duration(days: 180)); // Default 6 months

        await _storageService.saveGitHubTokenExpiresAt(accessTokenExpiry);
        await _storageService.saveGitHubRefreshTokenExpiresAt(
          refreshTokenExpiry,
        );

        debugPrint(
          '[GitHubAuth] Access token expires at: ${accessTokenExpiry.toIso8601String()}',
        );
        debugPrint(
          '[GitHubAuth] Refresh token expires at: ${refreshTokenExpiry.toIso8601String()}',
        );
      } else {
        debugPrint('[GitHubAuth] ℹ️  Token expiration not enabled');
      }

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

  /// Manually refresh the access token if needed
  /// This can be called before making API calls to ensure token is valid
  Future<bool> ensureValidToken() async {
    if (!state.isAuthenticated || state.accessToken == null) {
      return false;
    }

    // Check if token needs refresh
    if (await _shouldRefreshToken()) {
      return await _refreshAccessToken();
    }

    return true; // Token is still valid
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

      // First verify token is still valid
      final isValid = await _verifyToken(state.accessToken!);

      if (!isValid) {
        // Token is invalid (revoked)
        debugPrint('[GitHubAuth] ❌ Token was revoked during refresh');
        await _storageService.deleteGitHubToken();
        _apiService.clearAccessToken();
        state = state.copyWith(
          isAuthenticated: false,
          accessToken: null,
          installationToken: null,
          installationId: null,
          user: null,
          needsReauth: true,
          error:
              'Your GitHub access has been revoked. Please reconnect to continue syncing.',
        );
        return;
      }

      final user = await _apiService.getAuthenticatedUser();

      if (user != null) {
        state = state.copyWith(user: user, needsReauth: false);
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

  /// Handle API errors - detects token revocation and updates state accordingly
  /// Call this from any code that gets a 401 error from GitHub API
  Future<void> handleApiError(int statusCode) async {
    if (statusCode == 401) {
      debugPrint('[GitHubAuth] ❌ Detected 401 error - token was revoked');
      await _storageService.deleteGitHubToken();
      _apiService.clearAccessToken();
      state = state.copyWith(
        isAuthenticated: false,
        accessToken: null,
        installationToken: null,
        installationId: null,
        user: null,
        needsReauth: true,
        error:
            'Your GitHub access has been revoked. Please reconnect to continue syncing.',
      );
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
