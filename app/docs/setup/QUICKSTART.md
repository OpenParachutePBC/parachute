# Quick Start: Testing GitHub OAuth

Get GitHub OAuth working in **under 5 minutes**.

## Step 1: Register GitHub OAuth App (2 minutes)

1. Go to https://github.com/settings/developers
2. Click **"OAuth Apps"** → **"New OAuth App"**
3. Fill in:
   - **Application name**: `Parachute Dev`
   - **Homepage URL**: `https://github.com/yourusername/parachute`
   - **Authorization callback URL**: `open-parachute://auth/github/callback`
4. Click **"Register application"**
5. Click **"Generate a new client secret"**
6. **Keep this page open** (you'll need these values)

## Step 2: Configure App (1 minute)

```bash
# In the project root
cp .env.example .env

# Edit .env and add your credentials
# (Open the file and paste your Client ID and Secret)
```

Your `.env` should look like:
```env
GITHUB_CLIENT_ID=Iv1.abc123def456
GITHUB_CLIENT_SECRET=your_secret_here_1234567890abcdef
```

**Important**:
- The `.env` file is at the project root
- File is git-ignored automatically
- No quotes around values needed

## Step 3: Run the App (2 minutes)

```bash
flutter run -d macos

# Or for iOS/Android:
# flutter run -d iPhone
# flutter run -d android
```

That's it! No `--dart-define` needed when using `.env`.

## Step 4: Test OAuth Flow

1. App opens → go to **Settings** tab
2. Find **"Git Sync (Multi-Device)"** card
3. Click **"Connect with GitHub (Recommended)"**
4. Browser opens → click **"Authorize"**
5. App shows your GitHub username ✅
6. Select a repository or create new one
7. Click **"Complete Setup"**
8. Done! 🎉

## Troubleshooting

**"Authorization callback URL mismatch"**
- Double-check it's exactly: `open-parachute://auth/github/callback`
- No trailing slash!

**"No .env file found" in logs**
- That's OK! It means you're using `--dart-define` or defaults
- Only an error if credentials don't work

**Browser doesn't redirect back to app**
- Try running from Xcode once (registers URL scheme on macOS)
- Test deep link: `open "open-parachute://test"`

**Still stuck?**
- See full guide: `docs/setup/github-oauth-testing.md`
- Check logs for `[GitHubOAuth]` messages

## Alternative: Using --dart-define

If you prefer not to use `.env`:

```bash
flutter run -d macos \
  --dart-define=GITHUB_CLIENT_ID=Iv1.your_id \
  --dart-define=GITHUB_CLIENT_SECRET=your_secret
```

Both methods work! `.env` is just more convenient for development.

## Next Steps

Once working:
- Test repository creation
- Test manual sync
- Test auto-sync after recording
- Try on iOS/Android

See `docs/setup/github-oauth-testing.md` for comprehensive testing checklist.
