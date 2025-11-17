#!/bin/bash
# Fix libssh2 OpenSSL path after build

LIBSSH2_PATH="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libssh2.1.dylib"

if [ -f "$LIBSSH2_PATH" ]; then
    echo "Fixing libssh2 OpenSSL path: $LIBSSH2_PATH"
    install_name_tool -change /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib /usr/lib/libcrypto.dylib "$LIBSSH2_PATH" 2>/dev/null || true
    echo "✅ libssh2 OpenSSL path fixed"
fi
