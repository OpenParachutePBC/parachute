# GitHub App Setup for Parachute

This document explains how to set up the GitHub App for Parachute's secure, repository-scoped Git sync feature.

## Why GitHub App (Not OAuth App)?

GitHub Apps provide better security than OAuth Apps:

- ✅ **Fine-grained permissions** - Only request Contents: Read/Write
- ✅ **Repository-specific access** - Users authorize per-repository
- ✅ **Short-lived tokens** - Programmatically refresh tokens
- ✅ **Better UX** - Users can revoke access per-repository
- ❌ OAuth Apps use classic scopes (broader access to all repos)

## GitHub App Registration

### For Development (Local Testing)

1. **Register GitHub App**
   - Go to: https://github.com/settings/apps/new
   - Fill in details:
     - **GitHub App name**: `Parachute (Dev)`
     - **Homepage URL**: `https://github.com/yourusername/parachute`
     - **Callback URL**: `open-parachute://auth/github/callback`
     - **Setup URL**: Leave blank
     - **Webhook**: Uncheck "Active"

2. **Set Permissions**
   - Repository permissions:
     - **Contents**: Read and write
     - **Metadata**: Read-only (automatically included)

3. **Where can this GitHub App be installed?**
   - Select: "Any account"

4. **Save Credentials**
   - After creation, note down:
     - **App ID**: (e.g., `123456`)
     - **Client ID**: (e.g., `Iv1.abc123def456`)
     - **Client Secret**: Click "Generate a new client secret"

5. **Configure App Settings**
   - Create `.env` file in project root:
     ```env
     GITHUB_APP_ID=123456
     GITHUB_CLIENT_ID=Iv1.abc123def456
     GITHUB_CLIENT_SECRET=your_client_secret_here
     ```

### For Production (App Store Release)

1. **Use Production App Name**
   - **GitHub App name**: `Parachute`
   - **Homepage URL**: `https://parachute.app` (or your official site)
   - **Callback URL**: `open-parachute://auth/github/callback`

2. **Same Permissions as Development**
   - Repository permissions:
     - **Contents**: Read and write
     - **Metadata**: Read-only

3. **Store Secrets Securely**
   - Add credentials to CI/CD environment variables
   - **Never commit** `.env` file to version control
   - Use different credentials for dev vs production

## OAuth Flow

### User Authorization Flow

```
User taps "Connect GitHub" in app
          ↓
App opens browser with GitHub authorization URL:
https://github.com/login/oauth/authorize?
  client_id=Iv1.abc123def456
  &redirect_uri=open-parachute://auth/github/callback
  &state=random_state_token
          ↓
User authorizes app and selects repositories
          ↓
GitHub redirects to: open-parachute://auth/github/callback?code=ABC123&state=...
          ↓
App exchanges code for access token:
POST https://github.com/login/oauth/access_token
  client_id=Iv1.abc123def456
  &client_secret=your_secret
  &code=ABC123
          ↓
GitHub returns: access_token (for API) + installation_id (for Git operations)
          ↓
App uses access token to:
  - List user's repositories
  - Create new repositories
  - Get installation access token for Git sync
```

### Token Types

**1. OAuth Access Token** (from OAuth flow)

- Used for GitHub API calls
- Long-lived (no expiration unless revoked)
- Scope: Based on user authorization
- Used to list repos, create repos, etc.

**2. Installation Access Token** (from GitHub App API)

- Used for Git operations (clone, push, pull)
- Short-lived (expires after 1 hour)
- Automatically refreshed by app
- Scoped to specific repositories user authorized

## Implementation Files

- `lib/core/services/github/github_oauth_service.dart` - OAuth flow
- `lib/core/services/github/github_api_service.dart` - Repository API
- `lib/features/settings/screens/github_connect_wizard.dart` - UI flow
- `lib/core/providers/github_auth_provider.dart` - State management

## Testing Locally

1. Register development GitHub App (see above)
2. Add credentials to `.env` file (git-ignored)
3. Run app: `flutter run`
4. Go to Settings → Git Sync → Connect GitHub
5. Authorize app for test repository
6. Verify sync works

## Security Notes

- Client secret is embedded in app (standard for mobile OAuth)
- Tokens stored securely using `flutter_secure_storage`
- State parameter prevents CSRF attacks
- Installation tokens auto-refresh before expiration
- Users can revoke access at: https://github.com/settings/installations

## Troubleshooting

### "Callback URL not registered"

- Ensure `open-parachute://auth/github/callback` is added in GitHub App settings
- Check URL scheme in `Info.plist` (iOS) and `AndroidManifest.xml` (Android)

### "Repository not accessible"

- User must grant app access during authorization flow
- Check installation permissions: Settings → Applications → Installed GitHub Apps

### "Token expired"

- Installation tokens expire after 1 hour
- App should auto-refresh; check logs for refresh errors

## Resources

- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [Authenticating with GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app)
- [Repository permissions reference](https://docs.github.com/en/rest/overview/permissions-required-for-github-apps)
