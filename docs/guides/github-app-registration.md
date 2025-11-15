# GitHub App Registration Guide

This guide walks you through creating a GitHub App for Parachute's Git sync feature. **GitHub Apps** (not OAuth Apps) allow repository-specific access, ensuring your authentication token only works with the repositories you explicitly authorize.

---

## Why GitHub Apps?

**GitHub Apps** vs **OAuth Apps**:

| Feature               | GitHub Apps                                        | OAuth Apps                                  |
| --------------------- | -------------------------------------------------- | ------------------------------------------- |
| **Repository Access** | User selects specific repos during authorization   | Requests access to ALL public/private repos |
| **Token Scope**       | Repository-scoped (only authorized repos)          | Broad `repo` scope (all repos)              |
| **Security**          | More secure (installation tokens expire in 1 hour) | Less secure (tokens don't expire)           |
| **Permissions**       | Granular (Contents: Read/Write only)               | Broad (`repo` includes everything)          |

Parachute uses GitHub Apps to ensure your sync token **only** works with your vault repository.

---

## Step 1: Register a New GitHub App

1. **Go to GitHub Settings**:
   - Navigate to: https://github.com/settings/apps/new
   - Or: **GitHub Settings** → **Developer settings** → **GitHub Apps** → **New GitHub App**

2. **Fill in Basic Information**:

   | Field               | Value                                                      |
   | ------------------- | ---------------------------------------------------------- |
   | **GitHub App name** | `Parachute Sync` (or any unique name)                      |
   | **Homepage URL**    | `https://github.com/yourusername/parachute` (or your fork) |
   | **Callback URL**    | `open-parachute://auth/github/callback`                    |
   | **Setup URL**       | Leave empty                                                |
   | **Webhook**         | ❌ Uncheck "Active" (we don't need webhooks)               |

3. **Set Repository Permissions**:

   Under **Repository permissions**:
   - **Contents**: Select `Read and write`
   - Leave all other permissions as `No access`

4. **Set Account Permissions**:

   Leave all account permissions as `No access`

5. **User Authorization Settings** (CRITICAL):

   Under **Identifying and authorizing users**:
   - ✅ Check **Request user authorization (OAuth) during installation**
     - **⚠️ REQUIRED** - This combines installation + OAuth into one flow
     - Without this, users must manually install the app from GitHub settings
     - This enables the "Connect with GitHub" button to work seamlessly
   - ✅ Check **Expire user authorization tokens**
     - Tokens expire after 8 hours of inactivity (more secure)
     - Parachute auto-refreshes tokens when needed
   - ❌ Leave **Enable Device Flow** unchecked
     - Only needed for devices without browsers (CLI tools, smart TVs)
     - Not needed for Parachute

6. **Where can this GitHub App be installed?**:
   - ✅ Select **Only on this account** (recommended)
   - Or select **Any account** if you want to share your app

7. **Click "Create GitHub App"**

---

## Step 2: Get Your Client Credentials

After creating the app, you'll be redirected to your app's settings page.

1. **Copy Client ID**:
   - You'll see **Client ID** near the top
   - Copy this value (e.g., `Iv1.a1b2c3d4e5f6g7h8`)

2. **Generate Client Secret**:
   - Scroll down to **Client secrets**
   - Click **Generate a new client secret**
   - **IMPORTANT**: Copy this immediately (you can't view it again!)
   - It looks like: `1234567890abcdef1234567890abcdef12345678`

---

## Step 3: Configure Parachute

1. **Navigate to the Flutter app directory**:

   ```bash
   cd app/
   ```

2. **Create `.env` file** (if it doesn't exist):

   ```bash
   cp .env.example .env
   ```

3. **Edit `.env` file**:

   ```bash
   # Add your GitHub App credentials
   GITHUB_CLIENT_ID=Iv1.a1b2c3d4e5f6g7h8
   GITHUB_CLIENT_SECRET=1234567890abcdef1234567890abcdef12345678
   GITHUB_APP_SLUG=parachute-sync
   ```

   **Finding your app slug** (for automatic installation redirect):
   - Go to https://github.com/settings/apps
   - Click on your app
   - Look at the URL: `https://github.com/settings/apps/YOUR-APP-SLUG`
   - Copy the slug (e.g., `parachute-sync`)

4. **Save the file**

---

## Step 4: Create Your Vault Repository

Before installing the GitHub App, create a repository to store your Parachute data:

1. **Go to GitHub**:
   - Navigate to https://github.com/new

2. **Create a new repository**:
   - **Repository name**: `parachute-vault` (or any name you prefer)
   - **Visibility**: ✅ **Private** (recommended - keeps your notes private)
   - **Initialize repository**: ❌ Leave **unchecked** (Parachute will initialize it)
     - Don't add README
     - Don't add .gitignore
     - Don't add license

3. **Click "Create repository"**

You'll select this repository in the next step when installing your GitHub App.

---

## Step 5: Connect in Parachute

Now you're ready to connect! The GitHub App will be installed automatically when you authenticate:

---

## Step 6: Test in Parachute

1. **Run the app**:

   ```bash
   cd app/
   flutter run -d macos  # or -d chrome for web
   ```

2. **Open Settings**:
   - Navigate to **Settings** → **Git Sync**

3. **Click "Connect with GitHub"**:
   - Browser opens to GitHub authorization page
   - **Install the app** - GitHub will prompt you to install (first time only)
   - **Select repositories** - Choose your vault repository (from Step 4)
     - ✅ **Only select repositories** (recommended) - select just your vault repo
     - Or **All repositories** if you want to sync multiple vaults
   - **Authorize** - Click the green "Authorize" button

4. **Back in Parachute**:
   - You'll be redirected back to the app automatically
   - Select your vault repository from the list
   - Complete the setup wizard

---

## Troubleshooting

### "Invalid client credentials" error

**Cause**: Client ID or Client Secret is incorrect

**Fix**:

1. Verify your `.env` file has correct credentials
2. Make sure there are no extra spaces or quotes
3. Regenerate Client Secret if needed

### "No repositories found" or "GitHub App not installed" error

**Cause**: The "Request user authorization (OAuth) during installation" option wasn't enabled, so GitHub didn't prompt you to install the app

**Fix Option 1 - Enable OAuth During Installation (Recommended)**:

1. Go to your GitHub App settings: https://github.com/settings/apps
2. Click on your app name (e.g., "Parachute Sync")
3. Scroll to **Identifying and authorizing users**
4. ✅ Check **Request user authorization (OAuth) during installation**
5. Click **Save changes**
6. In Parachute, sign out and try "Connect with GitHub" again
7. GitHub should now prompt you to install the app and select repositories

**Fix Option 2 - Manual Installation**:

1. Go to https://github.com/settings/installations
2. Find your app and click "Configure"
3. Select repositories to authorize
4. Save
5. Try connecting again in Parachute

### "Callback URL mismatch" error

**Cause**: Callback URL in GitHub App settings doesn't match

**Fix**:

1. Go to your GitHub App settings
2. Verify **Callback URL** is: `open-parachute://auth/github/callback`
3. Save changes
4. Try again

### App shows ALL repositories (not just authorized ones)

**Cause**: You're using an OAuth App instead of a GitHub App

**Fix**:

1. Delete the OAuth App
2. Create a new **GitHub App** following this guide
3. Make sure you're at https://github.com/settings/apps/new (not `/oauth/applications`)

---

## Security Best Practices

1. **Never commit `.env` to git**:
   - The `.env` file is already in `.gitignore`
   - Keep your Client Secret private

2. **Regenerate secrets if compromised**:
   - Go to your GitHub App settings
   - Click "Revoke" next to the old secret
   - Generate a new one
   - Update your `.env` file

3. **Limit repository access**:
   - Only install the app on repositories you actually want to sync
   - You can change this anytime at https://github.com/settings/installations

4. **Review installed apps regularly**:
   - Check https://github.com/settings/installations
   - Revoke access for apps you no longer use

---

## How It Works

When you connect Parachute to GitHub:

1. **Authorization**: You select which repositories to authorize during GitHub App installation
2. **Installation ID**: GitHub assigns an installation ID tracking your authorized repos
3. **Installation Token**: Parachute gets a repository-scoped token (expires in 1 hour)
4. **Git Operations**: All git operations (clone, push, pull) use this repository-scoped token
5. **Token Refresh**: Parachute automatically refreshes the installation token when needed

**Key Security Feature**: The installation token ONLY works with repositories you explicitly authorized. Even if someone steals your token, they can't access other repositories.

---

## Alternative: OAuth Apps (Not Recommended)

If you prefer the traditional OAuth App approach (broader `repo` scope):

1. Go to: https://github.com/settings/developers
2. Click **OAuth Apps** → **New OAuth App**
3. Set **Callback URL** to: `open-parachute://auth/github/callback`
4. After creating, copy Client ID and Client Secret
5. Add to `.env` file

**Downside**: OAuth Apps request access to ALL your repositories, which is less secure than GitHub Apps.

---

## Next Steps

After connecting GitHub:

1. **Create or select a repository** for your vault
2. **Enable auto-sync** in Settings → Git Sync
3. **Start recording** - your captures will auto-commit and push to GitHub
4. **Set up on another device** - clone your vault repository and start syncing

---

## Need Help?

- **GitHub Apps Documentation**: https://docs.github.com/en/apps
- **Parachute Issues**: https://github.com/yourusername/parachute/issues
- **Git Sync Architecture**: See [docs/implementation/github-sync-implementation.md](../implementation/github-sync-implementation.md)

---

**Last Updated**: November 15, 2025
