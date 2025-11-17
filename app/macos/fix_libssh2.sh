#!/bin/bash
# Fix libssh2 OpenSSL path to use system library instead of Homebrew
# This prevents macOS sandbox errors

LIBSSH2_PATH="$1"

if [ -f "$LIBSSH2_PATH" ]; then
    echo "Fixing libssh2 OpenSSL path: $LIBSSH2_PATH"
    install_name_tool -change /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib /usr/lib/libcrypto.dylib "$LIBSSH2_PATH" 2>/dev/null
    echo "✅ libssh2 OpenSSL path fixed"
else
    echo "⚠️  Warning: libssh2 not found at $LIBSSH2_PATH"
fi
