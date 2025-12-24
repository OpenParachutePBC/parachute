#!/bin/bash
# Install Android APK while preserving app data (settings, downloaded models, etc.)
#
# Usage:
#   ./scripts/install-android.sh          # Debug build (default)
#   ./scripts/install-android.sh release  # Release build
#   ./scripts/install-android.sh profile  # Profile build

set -e

cd "$(dirname "$0")/.."

BUILD_TYPE="${1:-debug}"

case "$BUILD_TYPE" in
  debug)
    APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
    echo "Building debug APK..."
    flutter build apk --debug
    ;;
  release)
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
    echo "Building release APK..."
    flutter build apk --release
    ;;
  profile)
    APK_PATH="build/app/outputs/flutter-apk/app-profile.apk"
    echo "Building profile APK..."
    flutter build apk --profile
    ;;
  *)
    echo "Unknown build type: $BUILD_TYPE"
    echo "Usage: $0 [debug|release|profile]"
    exit 1
    ;;
esac

if [ ! -f "$APK_PATH" ]; then
  echo "Error: APK not found at $APK_PATH"
  exit 1
fi

echo "Installing APK (preserving app data)..."
adb install -r "$APK_PATH"

echo "Done! App data preserved."
