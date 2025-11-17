#!/bin/bash
# Post-build script to fix macOS Git libraries
# Run this after: flutter build macos

APP_PATH="app/build/macos/Build/Products/Debug/Parachute.app/Contents/MacOS/libssh2.1.dylib"

if [ -f "$APP_PATH" ]; then
    echo "Fixing libssh2 OpenSSL path..."
    install_name_tool -change /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib /usr/lib/libcrypto.dylib "$APP_PATH"
    echo "✅ macOS Git libraries fixed"
else
    echo "⚠️  App not found. Build first with: cd app && flutter build macos --debug"
    exit 1
fi
