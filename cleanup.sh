#!/bin/bash
# Apple Codesign & Notarize - Cleanup Script
# Removes the temporary keychain created during signing

if [ -n "$APPLE_SIGN_KEYCHAIN_PATH" ] && [ -f "$APPLE_SIGN_KEYCHAIN_PATH" ]; then
    echo "Removing temporary keychain..."
    security delete-keychain "$APPLE_SIGN_KEYCHAIN_PATH" 2>/dev/null || true
    echo "  ✓ Keychain removed"
fi

# Clean up any leftover certificate files (should already be deleted)
rm -f "$RUNNER_TEMP/installer_cert.p12" 2>/dev/null || true
rm -f "$RUNNER_TEMP/app_cert.p12" 2>/dev/null || true
