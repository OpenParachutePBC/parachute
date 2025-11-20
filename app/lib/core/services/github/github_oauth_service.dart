import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// GitHub App OAuth service for authenticating users
///
/// This service implements the GitHub App installation flow with repository-specific access.
/// Unlike OAuth Apps (which have broad repo scope), GitHub Apps allow users to select
/// which specific repositories to authorize during the OAuth flow.
///
/// Flow:
/// 1. User taps "Connect GitHub" → opens browser
/// 2. User authorizes app and SELECTS SPECIFIC REPOSITORIES
/// 3. GitHub redirects to app with authorization code
/// 4. App exchanges code for user access token
/// 5. App gets installation ID for the selected repositories
/// 6. App requests installation access token (repository-specific)
/// 7. Token is used for API calls and Git operations (scoped to selected repos only)
class GitHubOAuthService {
  GitHubOAuthService._internal();
  static final GitHubOAuthService instance = GitHubOAuthService._internal();

  /// Get client ID from environment (.env file or --dart-define)
  static String get _clientId {
    // Try dart-define first (for CI/CD and command-line usage)
    const fromDefine = String.fromEnvironment('GITHUB_CLIENT_ID');
    if (fromDefine.isNotEmpty) return fromDefine;

    // Fall back to .env file (for local development)
    return dotenv.get('GITHUB_CLIENT_ID', fallback: 'YOUR_GITHUB_CLIENT_ID');
  }

  /// Get client secret from environment (.env file or --dart-define)
  static String get _clientSecret {
    // Try dart-define first (for CI/CD and command-line usage)
    const fromDefine = String.fromEnvironment('GITHUB_CLIENT_SECRET');
    if (fromDefine.isNotEmpty) return fromDefine;

    // Fall back to .env file (for local development)
    return dotenv.get(
      'GITHUB_CLIENT_SECRET',
      fallback: 'YOUR_GITHUB_CLIENT_SECRET',
    );
  }

  /// Get app slug from environment (.env file or --dart-define)
  static String get _appSlug {
    // Try dart-define first (for CI/CD and command-line usage)
    const fromDefine = String.fromEnvironment('GITHUB_APP_SLUG');
    if (fromDefine.isNotEmpty) return fromDefine;

    // Fall back to .env file (for local development)
    return dotenv.get('GITHUB_APP_SLUG', fallback: '');
  }

  static const String _redirectUri = 'open-parachute://auth/github/callback';
  static const String _authorizationEndpoint =
      'https://github.com/login/oauth/authorize';
  static const String _tokenEndpoint =
      'https://github.com/login/oauth/access_token';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription? _linkSubscription;
  Completer<Map<String, dynamic>>? _authCompleter;
  String? _currentState;

  /// Get the app slug (for installation URL)
  String get appSlug => _appSlug;

  /// Start the GitHub OAuth flow
  ///
  /// Opens the browser for user authorization and waits for the callback.
  /// For GitHub Apps with "Request user authorization (OAuth) during installation" enabled,
  /// this uses the installation URL which prompts the user to install the app and select
  /// repositories, then automatically redirects through OAuth.
  ///
  /// Returns a map containing:
  /// - access_token: OAuth access token for API calls
  /// - token_type: "bearer"
  /// - scope: Granted scopes
  /// - refresh_token (optional): Refresh token if expiration is enabled
  /// - expires_in (optional): Seconds until access token expires (8 hours)
  /// - refresh_token_expires_in (optional): Seconds until refresh token expires (6 months)
  Future<Map<String, dynamic>?> authorize() async {
    try {
      debugPrint('[GitHubOAuth] Starting authorization flow...');

      // Generate random state for CSRF protection
      _currentState = _generateRandomString(32);

      // Build authorization URL
      // For GitHub Apps, always use the OAuth endpoint (not installation URL)
      // When "Request user authorization (OAuth) during installation" is enabled:
      // - If app not installed: GitHub prompts installation + repo selection, then auto-redirects to OAuth
      // - If already installed: GitHub skips installation and just completes OAuth authorization
      // This works for both first-time and returning users!
      final authUrl = Uri.parse(_authorizationEndpoint).replace(
        queryParameters: {
          'client_id': _clientId,
          'redirect_uri': _redirectUri,
          'state': _currentState,
        },
      );

      debugPrint('[GitHubOAuth] Using OAuth authorization endpoint');

      debugPrint('[GitHubOAuth] Authorization URL: $authUrl');

      // Set up deep link listener before opening browser
      _authCompleter = Completer<Map<String, dynamic>>();
      _setupDeepLinkListener();

      // Open browser for authorization
      // Note: Don't use canLaunchUrl on Android - it returns false for HTTPS URLs
      // Just try to launch directly and catch errors
      try {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('[GitHubOAuth] ❌ Could not launch authorization URL: $e');
        _cleanup();
        return null;
      }

      // Wait for callback (with timeout)
      final result = await _authCompleter!.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          debugPrint('[GitHubOAuth] ❌ Authorization timed out');
          _cleanup();
          throw TimeoutException('Authorization timed out');
        },
      );

      _cleanup();
      return result;
    } catch (e) {
      debugPrint('[GitHubOAuth] ❌ Error during authorization: $e');
      _cleanup();
      return null;
    }
  }

  /// Set up listener for deep link callback from GitHub
  void _setupDeepLinkListener() {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri? uri) async {
        if (uri != null) {
          debugPrint('[GitHubOAuth] Received deep link: $uri');
          await _handleCallback(uri.toString());
        }
      },
      onError: (err) {
        debugPrint('[GitHubOAuth] ❌ Deep link error: $err');
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.completeError(err);
        }
      },
    );
  }

  /// Handle the OAuth callback with authorization code
  Future<void> _handleCallback(String link) async {
    try {
      final uri = Uri.parse(link);

      // Verify this is our callback
      if (!link.startsWith(_redirectUri)) {
        debugPrint('[GitHubOAuth] ⚠️  Not our callback, ignoring');
        return;
      }

      // Extract query parameters
      final code = uri.queryParameters['code'];
      final state = uri.queryParameters['state'];
      final error = uri.queryParameters['error'];
      final installationIdStr = uri.queryParameters['installation_id'];
      final setupAction = uri.queryParameters['setup_action'];

      // Check for errors
      if (error != null) {
        debugPrint('[GitHubOAuth] ❌ Authorization error: $error');
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.completeError(
            Exception('Authorization error: $error'),
          );
        }
        return;
      }

      // Verify state (CSRF protection)
      if (state != _currentState) {
        debugPrint('[GitHubOAuth] ❌ State mismatch (CSRF protection)');
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.completeError(Exception('Invalid state parameter'));
        }
        return;
      }

      // Exchange code for access token
      if (code != null) {
        debugPrint('[GitHubOAuth] Exchanging code for access token...');
        final token = await _exchangeCodeForToken(code);

        if (token != null &&
            _authCompleter != null &&
            !_authCompleter!.isCompleted) {
          // Include installation_id if provided in callback
          if (installationIdStr != null) {
            debugPrint(
              '[GitHubOAuth] ✅ Installation ID from callback: $installationIdStr',
            );
            token['installation_id'] = installationIdStr;
          }
          if (setupAction != null) {
            debugPrint('[GitHubOAuth] Setup action: $setupAction');
            token['setup_action'] = setupAction;
          }
          _authCompleter!.complete(token);
        } else if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.completeError(
            Exception('Failed to exchange code for token'),
          );
        }
      } else {
        debugPrint('[GitHubOAuth] ❌ No authorization code received');
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.completeError(
            Exception('No authorization code received'),
          );
        }
      }
    } catch (e) {
      debugPrint('[GitHubOAuth] ❌ Error handling callback: $e');
      if (_authCompleter != null && !_authCompleter!.isCompleted) {
        _authCompleter!.completeError(e);
      }
    }
  }

  /// Exchange authorization code for access token
  Future<Map<String, dynamic>?> _exchangeCodeForToken(String code) async {
    try {
      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'code': code,
          'redirect_uri': _redirectUri,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        debugPrint('[GitHubOAuth] ✅ Token exchange successful');
        debugPrint('[GitHubOAuth] Token type: ${data['token_type']}');
        debugPrint('[GitHubOAuth] Scope: ${data['scope']}');

        // Check if refresh token is provided (only when expiration is enabled)
        final hasRefreshToken = data.containsKey('refresh_token');
        final hasExpiresIn = data.containsKey('expires_in');

        if (hasRefreshToken && hasExpiresIn) {
          debugPrint('[GitHubOAuth] ✅ Token expiration enabled');
          debugPrint(
            '[GitHubOAuth] Access token expires in: ${data['expires_in']} seconds (8 hours)',
          );
          debugPrint(
            '[GitHubOAuth] Refresh token expires in: ${data['refresh_token_expires_in']} seconds (6 months)',
          );
        } else {
          debugPrint('[GitHubOAuth] ℹ️  Token expiration not enabled');
        }

        return {
          'access_token': data['access_token'] as String,
          'token_type': data['token_type'] as String,
          'scope': data['scope'] as String? ?? '',
          if (hasRefreshToken) 'refresh_token': data['refresh_token'] as String,
          if (hasExpiresIn) 'expires_in': data['expires_in'] as int,
          if (data.containsKey('refresh_token_expires_in'))
            'refresh_token_expires_in': data['refresh_token_expires_in'] as int,
        };
      } else {
        debugPrint(
          '[GitHubOAuth] ❌ Token exchange failed: ${response.statusCode}',
        );
        debugPrint('[GitHubOAuth] Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[GitHubOAuth] ❌ Error exchanging code for token: $e');
      return null;
    }
  }

  /// Refresh an expired access token using a refresh token
  ///
  /// Returns a map containing:
  /// - access_token: New access token (expires in 8 hours)
  /// - refresh_token: New refresh token (expires in 6 months)
  /// - expires_in: Seconds until access token expires (28800 = 8 hours)
  /// - refresh_token_expires_in: Seconds until refresh token expires (15897600 = 6 months)
  Future<Map<String, dynamic>?> refreshAccessToken(String refreshToken) async {
    try {
      debugPrint('[GitHubOAuth] 🔄 Refreshing access token...');

      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        debugPrint('[GitHubOAuth] ✅ Token refresh successful');
        debugPrint(
          '[GitHubOAuth] New access token expires in: ${data['expires_in']} seconds',
        );
        debugPrint(
          '[GitHubOAuth] New refresh token expires in: ${data['refresh_token_expires_in']} seconds',
        );

        return {
          'access_token': data['access_token'] as String,
          'refresh_token': data['refresh_token'] as String,
          'token_type': data['token_type'] as String,
          'expires_in': data['expires_in'] as int,
          'refresh_token_expires_in': data['refresh_token_expires_in'] as int,
          'scope': data['scope'] as String? ?? '',
        };
      } else {
        debugPrint(
          '[GitHubOAuth] ❌ Token refresh failed: ${response.statusCode}',
        );
        debugPrint('[GitHubOAuth] Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[GitHubOAuth] ❌ Error refreshing token: $e');
      return null;
    }
  }

  /// Generate a random string for state parameter (CSRF protection)
  String _generateRandomString(int length) {
    final random = List.generate(length, (i) => i);
    final bytes = sha256.convert(random).bytes;
    return base64Url.encode(bytes).substring(0, length);
  }

  /// Clean up resources
  void _cleanup() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _authCompleter = null;
    _currentState = null;
  }

  /// Open the GitHub App installation page
  ///
  /// This directs the user to install the app and select repositories.
  /// After installation, they should return to the app and try "Connect with GitHub" again.
  Future<void> openInstallationPage() async {
    if (_appSlug.isEmpty) {
      debugPrint(
        '[GitHubOAuth] ❌ No app slug configured, cannot open installation page',
      );
      return;
    }

    final installUrl = Uri.parse(
      'https://github.com/apps/$_appSlug/installations/new',
    );
    debugPrint('[GitHubOAuth] Opening installation page: $installUrl');

    try {
      await launchUrl(installUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[GitHubOAuth] ❌ Could not launch installation URL: $e');
    }
  }

  /// Get user's installations (which repositories they've authorized)
  ///
  /// Returns installation ID if user has installed the app
  Future<int?> getUserInstallationId(String accessToken) async {
    try {
      debugPrint('[GitHubOAuth] Getting user installations...');

      final response = await http.get(
        Uri.parse('https://api.github.com/user/installations'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $accessToken',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final installations = data['installations'] as List<dynamic>;

        if (installations.isNotEmpty) {
          final installationId = installations[0]['id'] as int;
          debugPrint('[GitHubOAuth] ✅ Found installation ID: $installationId');
          return installationId;
        } else {
          debugPrint('[GitHubOAuth] ⚠️  No installations found');
          return null;
        }
      } else {
        debugPrint(
          '[GitHubOAuth] ❌ Failed to get installations: ${response.statusCode}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('[GitHubOAuth] ❌ Error getting installations: $e');
      return null;
    }
  }

  /// Get installation access token (repository-specific token)
  ///
  /// This token is scoped to only the repositories the user authorized
  /// Returns a map with:
  /// - token: Installation access token
  /// - expires_at: Token expiration time (typically 1 hour)
  Future<Map<String, dynamic>?> getInstallationAccessToken({
    required String userAccessToken,
    required int installationId,
  }) async {
    try {
      debugPrint(
        '[GitHubOAuth] Getting installation access token for installation: $installationId',
      );

      final response = await http.post(
        Uri.parse(
          'https://api.github.com/app/installations/$installationId/access_tokens',
        ),
        headers: {
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $userAccessToken',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('[GitHubOAuth] ✅ Got installation access token');
        debugPrint('[GitHubOAuth] Token expires at: ${data['expires_at']}');

        return {
          'token': data['token'] as String,
          'expires_at': data['expires_at'] as String,
        };
      } else {
        debugPrint(
          '[GitHubOAuth] ❌ Failed to get installation token: ${response.statusCode}',
        );
        debugPrint('[GitHubOAuth] Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[GitHubOAuth] ❌ Error getting installation access token: $e');
      return null;
    }
  }

  /// Dispose of the service
  void dispose() {
    _cleanup();
  }
}
