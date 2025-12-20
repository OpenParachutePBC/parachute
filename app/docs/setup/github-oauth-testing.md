# Testing GitHub OAuth Integration

This guide explains how to test the new GitHub OAuth-based Git sync feature.

## Prerequisites

1. **GitHub Account** - You need a GitHub account
2. **Development Environment** - Flutter and Xcode/Android Studio set up
3. **GitHub OAuth App** - Registered GitHub OAuth App (see below)

## Step 1: Register GitHub OAuth App

### For Development/Testing

1. Go to https://github.com/settings/developers
2. Click "OAuth Apps" → "New OAuth App"
3. Fill in the form:
   - **Application name**: `Parachute (Dev)`
   - **Homepage URL**: `https://github.com/yourusername/parachute`
   - **Application description**: `Parachute vault sync - Development`
   - **Authorization callback URL**: `open-parachute://auth/github/callback`
4. Click "Register application"
5. Note down your **Client ID** (e.g., `Iv1.abc123def456`)
6. Click "Generate a new client secret"
7. Note down your **Client Secret** (keep this secure!)

### Important: OAuth App vs GitHub App

For simplicity during development, we're using **OAuth Apps** which provide:
- ✅ Simple setup (no installation required)
- ✅ Straightforward OAuth flow
- ❌ Broad `repo` scope (access to all repos)

For production, we recommend creating a **GitHub App** instead (see `docs/setup/github-app-setup.md`) which provides:
- ✅ Fine-grained permissions
- ✅ Repository-specific access
- ✅ Better security

**Note**: The current implementation works with both OAuth Apps and GitHub Apps.

## Step 2: Configure Environment Variables

There are two ways to provide the credentials to the app:

### Option A: Using dart-define (Recommended for Development)

Run the app with credentials passed as arguments:

```bash


# macOS
flutter run -d macos \
  --dart-define=GITHUB_CLIENT_ID=Iv1.your_client_id_here \
  --dart-define=GITHUB_CLIENT_SECRET=your_client_secret_here

# iOS (simulator)
flutter run -d iPhone \
  --dart-define=GITHUB_CLIENT_ID=Iv1.your_client_id_here \
  --dart-define=GITHUB_CLIENT_SECRET=your_client_secret_here

# Android
flutter run -d android \
  --dart-define=GITHUB_CLIENT_ID=Iv1.your_client_id_here \
  --dart-define=GITHUB_CLIENT_SECRET=your_client_secret_here
```

### Option B: Using .env file (Alternative)

1. Copy the example file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and add your credentials:
   ```env
   GITHUB_CLIENT_ID=Iv1.your_client_id_here
   GITHUB_CLIENT_SECRET=your_client_secret_here
   ```

3. **Note**: This requires additional setup to load env vars at compile time. Use Option A for now.

## Step 3: Test the OAuth Flow

1. **Launch the app**:
   ```bash
   
   flutter run -d macos \
     --dart-define=GITHUB_CLIENT_ID=YOUR_ID \
     --dart-define=GITHUB_CLIENT_SECRET=YOUR_SECRET
   ```

2. **Navigate to Settings**:
   - Open the app
   - Go to Settings tab
   - Find the "Git Sync (Multi-Device)" card

3. **Click "Connect with GitHub (Recommended)"**:
   - This opens the GitHub OAuth wizard
   - Step 1: Authenticate with GitHub

4. **Authorize in Browser**:
   - Browser opens with GitHub authorization page
   - Review permissions requested
   - Click "Authorize" button
   - Browser redirects back to app with `open-parachute://auth/github/callback?code=...`

5. **Select Repository**:
   - Step 2: Choose existing repo OR create new one
   - Search for repos or click "Create New Repository"
   - If creating new:
     - Enter name (e.g., `parachute-vault`)
     - Choose Private (recommended)
     - Click "Create Repository"

6. **Complete Setup**:
   - Step 3: Review selected repository
   - Click "Complete Setup"
   - App configures Git sync automatically

7. **Verify Sync Works**:
   - Create a new voice recording or capture
   - Check that "Git Sync" status shows recent sync
   - Go to your GitHub repository
   - Verify files are synced

## Expected Behavior

### Success Path

1. ✅ Browser opens to GitHub authorization page
2. ✅ After authorizing, app receives callback
3. ✅ User info loads (shows GitHub username/avatar)
4. ✅ Repository list loads
5. ✅ Can create new repository
6. ✅ Git sync sets up automatically
7. ✅ Captures auto-sync to GitHub

### Common Issues

**Issue**: Browser doesn't redirect back to app
- **Solution**: Verify callback URL in GitHub app settings: `open-parachute://auth/github/callback`
- **Check**: Run `flutter clean && flutter run` to reload manifests

**Issue**: "No access token received"
- **Solution**: Check client ID and secret are correct
- **Verify**: Client secret hasn't expired

**Issue**: Repository list is empty
- **Reason**: You may not have any repositories yet
- **Solution**: Use "Create New Repository" button

**Issue**: Deep link not working on macOS
- **Solution**: Ensure app is built from Xcode first time (needed to register URL scheme)
- **Run**: `open -a Parachute.app open-parachute://test` to test deep linking

## Testing Checklist

- [ ] OAuth flow completes successfully
- [ ] GitHub user info displays correctly
- [ ] Repository list loads
- [ ] Can search repositories
- [ ] Can create new repository
- [ ] Git sync configures automatically
- [ ] Manual sync works ("Sync Now" button)
- [ ] Auto-sync triggers after recording save
- [ ] Files appear in GitHub repository
- [ ] Can disconnect and reconnect
- [ ] Deep linking works on all platforms

## Manual Testing (Advanced Users Only)

The old manual setup is still available as "Manual Setup (Advanced)" button:

1. Create a Personal Access Token at https://github.com/settings/tokens
2. Grant `repo` scope
3. Copy token
4. Enter repository URL and token manually
5. Click "Manual Setup"

This is useful for testing or for users who prefer manual control.

## Debugging

### Enable verbose logging

Check Flutter console for debug messages:
- `[GitHubOAuth]` - OAuth flow logs
- `[GitHubAPI]` - API call logs
- `[GitHubAuth]` - Authentication state logs
- `[GitService]` - Git operations logs

### Test deep linking directly

```bash
# macOS
open "open-parachute://auth/github/callback?code=test123&state=test"

# iOS Simulator
xcrun simctl openurl booted "open-parachute://auth/github/callback?code=test123&state=test"

# Android
adb shell am start -a android.intent.action.VIEW -d "open-parachute://auth/github/callback?code=test123&state=test"
```

### Verify URL schemes are registered

**iOS/macOS**: Check Info.plist has `CFBundleURLSchemes` with `parachute`
**Android**: Check AndroidManifest.xml has intent-filter with `scheme="parachute"`

## Next Steps

Once OAuth is working:
1. Test on all target platforms (iOS, Android, macOS)
2. Test with real voice recordings
3. Verify sync happens in background
4. Test conflict resolution (edit same file on two devices)
5. Test with large vaults (100+ recordings)

## Production Deployment

Before releasing to users:
1. Create production GitHub App (not OAuth App)
2. Use environment-specific client IDs
3. Set up proper secret management (GitHub Secrets, AWS Secrets Manager, etc.)
4. Test on physical devices
5. Add error handling for network failures
6. Add retry logic for failed syncs
7. Monitor GitHub API rate limits

See `docs/setup/github-app-setup.md` for production setup details.
