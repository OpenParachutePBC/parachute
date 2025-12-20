# Parachute - Setup Guide

**Last Updated:** December 8, 2025

This guide will help you set up your development environment for the Parachute Flutter app.

---

## Prerequisites

### Required Software

1. **Flutter 3.24+**
2. **Git**

### Optional

- **VSCode** with Flutter extension
- **Android Studio** (for Android development)
- **Xcode** (for iOS/macOS development, macOS only)

---

## Installation Steps

### 1. Install Flutter

**macOS (Homebrew):**
```bash
brew install --cask flutter

# Verify
flutter doctor
```

**Linux:**
```bash
# Download from https://docs.flutter.dev/get-started/install/linux
cd ~/development
wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.x-stable.tar.xz
tar xf flutter_linux_3.24.x-stable.tar.xz

# Add to PATH (add to ~/.bashrc or ~/.zshrc)
export PATH="$PATH:~/development/flutter/bin"

# Verify
flutter doctor
```

**Windows:**
- Download from https://docs.flutter.dev/get-started/install/windows
- Extract to C:\src\flutter
- Add to PATH
- Verify: `flutter doctor`

**Run Flutter Doctor:**
```bash
flutter doctor
```

This will check for:
- Flutter SDK
- Android toolchain (for Android development)
- Xcode (for iOS/macOS development, macOS only)
- Chrome (for web development)

Follow any recommendations from `flutter doctor` to complete setup.

---

## Platform-Specific Setup

### macOS Development

```bash
# Already supported, no extra setup needed
flutter config --enable-macos-desktop
```

### iOS Development (macOS only)

1. **Install Xcode:**
   - Download from Mac App Store or https://developer.apple.com/xcode/

2. **Accept Xcode license:**
   ```bash
   sudo xcodebuild -license accept
   ```

3. **Install CocoaPods:**
   ```bash
   sudo gem install cocoapods
   ```

### Android Development

1. **Install Android Studio:**
   - Download from https://developer.android.com/studio

2. **Install Android SDK:**
   - Open Android Studio
   - SDK Manager → Install latest Android SDK
   - Install Android SDK Command-line Tools

3. **Accept Android licenses:**
   ```bash
   flutter doctor --android-licenses
   ```

4. **Create Android emulator:**
   - Tools → AVD Manager → Create Virtual Device
   - Choose Pixel 5 or similar
   - Download system image (API 33+ recommended)

### Web Development

Works out of the box with Chrome:

```bash
flutter devices
# Should show Chrome listed
```

---

## Project Setup

### Clone Repository

```bash
git clone https://github.com/OpenParachutePBC/parachute.git
cd parachute
```

### Install Dependencies

```bash
flutter pub get
```

### Run the App

```bash
# macOS
flutter run -d macos

# Android
flutter run -d android

# Web
flutter run -d chrome

# iOS (macOS only)
flutter run -d ios
```

---

## Environment Setup (Optional)

For GitHub sync features, create a `.env` file:

```bash
cp .env.example .env
```

Edit `.env` with your GitHub OAuth credentials (see [github-oauth-testing.md](github-oauth-testing.md)).

---

## Verify Installation

```bash
# Run tests
flutter test

# Run the app
flutter run -d macos
```

App should launch and show the Parachute home screen with three tabs: Spheres, Recorder, and Files.

---

## Troubleshooting

### Flutter Issues

**Problem:** `flutter: command not found`
**Solution:** Add Flutter to PATH in ~/.bashrc or ~/.zshrc

**Problem:** "Android licenses not accepted"
**Solution:** Run `flutter doctor --android-licenses`

**Problem:** "Xcode not properly configured"
**Solution:**
```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

**Problem:** Build fails with dependency errors
**Solution:**
```bash
flutter clean
flutter pub get
```

### macOS Specific

**Problem:** App crashes on launch
**Solution:** Check entitlements in `macos/Runner/DebugProfile.entitlements`

### Android Specific

**Problem:** Emulator won't start
**Solution:** Ensure virtualization is enabled in BIOS/UEFI

---

## IDE Setup

### VSCode (Recommended)

**Install Extensions:**
- Flutter (by Dart Code)
- Dart (by Dart Code)

**Settings:**
The project includes `.vscode/settings.json` with recommended settings.

### Android Studio

- Flutter and Dart plugins should be installed
- Open the project root directory

---

## Next Steps

1. Read [workflow.md](../development/workflow.md) for development workflow
2. Read [testing.md](../development/testing.md) for testing guide
3. Review [CLAUDE.md](../../CLAUDE.md) for project context

---

**Last Updated:** December 8, 2025
