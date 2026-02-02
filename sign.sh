#!/bin/bash
# Apple Codesign & Notarize - Main Script
# Signs bundles and packages, optionally notarizes and staples

set -e

# Initialize outputs with defaults
echo "signed=false" >> $GITHUB_OUTPUT
echo "notarized=false" >> $GITHUB_OUTPUT
echo "stapled=false" >> $GITHUB_OUTPUT
echo "can_sign_app=false" >> $GITHUB_OUTPUT
echo "can_sign_pkg=false" >> $GITHUB_OUTPUT
echo "can_notarize=false" >> $GITHUB_OUTPUT

# ============================================================================
# Validate inputs
# ============================================================================

if [ -z "$INPUT_INSTALLER_CERTIFICATE" ]; then
    echo "::error::installer-certificate is required"
    exit 1
fi

if [ -z "$INPUT_INSTALLER_CERTIFICATE_PASSWORD" ]; then
    echo "::error::installer-certificate-password is required"
    exit 1
fi

if [ -z "$INPUT_PACKAGE_PATH" ]; then
    echo "::error::package-path is required"
    exit 1
fi

if [ ! -f "$INPUT_PACKAGE_PATH" ]; then
    echo "::error::Package not found: $INPUT_PACKAGE_PATH"
    exit 1
fi

# Determine output path
if [ -n "$INPUT_SIGNED_PACKAGE_PATH" ]; then
    SIGNED_PKG="$INPUT_SIGNED_PACKAGE_PATH"
else
    SIGNED_PKG="$INPUT_PACKAGE_PATH"
fi

# ============================================================================
# Create temporary keychain
# ============================================================================

echo "Creating temporary keychain..."
KEYCHAIN_PATH="$RUNNER_TEMP/signing-$$.keychain-db"
KEYCHAIN_PWD=$(openssl rand -base64 32)

# Export for cleanup script
echo "APPLE_SIGN_KEYCHAIN_PATH=$KEYCHAIN_PATH" >> $GITHUB_ENV

if ! security create-keychain -p "$KEYCHAIN_PWD" "$KEYCHAIN_PATH"; then
    echo "::error::Failed to create keychain"
    exit 1
fi

security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PWD" "$KEYCHAIN_PATH"

# ============================================================================
# Import certificates
# ============================================================================

# Import Developer ID Installer certificate (required)
echo "Importing Developer ID Installer certificate..."
echo "$INPUT_INSTALLER_CERTIFICATE" | base64 --decode > "$RUNNER_TEMP/installer_cert.p12"

if ! security import "$RUNNER_TEMP/installer_cert.p12" -k "$KEYCHAIN_PATH" \
    -P "$INPUT_INSTALLER_CERTIFICATE_PASSWORD" \
    -T /usr/bin/productsign -T /usr/bin/pkgbuild -T /usr/bin/productbuild; then
    echo "::error::Failed to import Installer certificate"
    rm -f "$RUNNER_TEMP/installer_cert.p12"
    exit 1
fi
rm -f "$RUNNER_TEMP/installer_cert.p12"
echo "  ✓ Installer certificate imported"
echo "can_sign_pkg=true" >> $GITHUB_OUTPUT

# Import Developer ID Application certificate (optional, for bundle signing)
CAN_SIGN_APP=false
if [ -n "$INPUT_APPLICATION_CERTIFICATE" ] && [ -n "$INPUT_APPLICATION_CERTIFICATE_PASSWORD" ]; then
    echo "Importing Developer ID Application certificate..."
    echo "$INPUT_APPLICATION_CERTIFICATE" | base64 --decode > "$RUNNER_TEMP/app_cert.p12"
    
    if security import "$RUNNER_TEMP/app_cert.p12" -k "$KEYCHAIN_PATH" \
        -P "$INPUT_APPLICATION_CERTIFICATE_PASSWORD" \
        -T /usr/bin/codesign; then
        echo "  ✓ Application certificate imported"
        CAN_SIGN_APP=true
        echo "can_sign_app=true" >> $GITHUB_OUTPUT
    else
        echo "::warning::Failed to import Application certificate — bundles will not be signed"
    fi
    rm -f "$RUNNER_TEMP/app_cert.p12"
fi

# Set keychain for signing
security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PWD" "$KEYCHAIN_PATH"

echo "  ✓ Keychain configured"

# ============================================================================
# Get signing identities from keychain
# ============================================================================

INSTALLER_IDENTITY=$(security find-identity -v "$KEYCHAIN_PATH" | grep "Developer ID Installer" | head -1 | sed 's/.*"\(.*\)".*/\1/')
if [ -z "$INSTALLER_IDENTITY" ]; then
    echo "::error::Could not find Developer ID Installer identity in keychain"
    exit 1
fi
echo "Using installer identity: $INSTALLER_IDENTITY"

APP_IDENTITY=""
if [ "$CAN_SIGN_APP" = true ]; then
    APP_IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    if [ -n "$APP_IDENTITY" ]; then
        echo "Using application identity: $APP_IDENTITY"
    fi
fi

# ============================================================================
# Sign bundles (if requested and certificate available)
# ============================================================================

if [ -n "$INPUT_SIGN_BUNDLES" ] && [ "$CAN_SIGN_APP" = true ] && [ -n "$APP_IDENTITY" ]; then
    echo ""
    echo "Signing bundles..."
    
    # Build codesign flags
    CODESIGN_FLAGS="--force --timestamp"
    if [ -n "$INPUT_CODESIGN_OPTIONS" ]; then
        CODESIGN_FLAGS="$CODESIGN_FLAGS --options $INPUT_CODESIGN_OPTIONS"
    fi
    if [ "$INPUT_CODESIGN_DEEP" = "true" ]; then
        CODESIGN_FLAGS="$CODESIGN_FLAGS --deep"
    fi
    
    # Process each bundle path (newline or space separated)
    echo "$INPUT_SIGN_BUNDLES" | tr ' ' '\n' | while read -r BUNDLE_PATH; do
        # Skip empty lines
        [ -z "$BUNDLE_PATH" ] && continue
        
        if [ ! -e "$BUNDLE_PATH" ]; then
            echo "::warning::Bundle not found, skipping: $BUNDLE_PATH"
            continue
        fi
        
        BUNDLE_NAME=$(basename "$BUNDLE_PATH")
        echo "  Signing $BUNDLE_NAME..."
        
        if codesign $CODESIGN_FLAGS --sign "$APP_IDENTITY" "$BUNDLE_PATH"; then
            # Verify
            if codesign --verify --deep --strict "$BUNDLE_PATH" 2>/dev/null; then
                echo "    ✓ $BUNDLE_NAME signed and verified"
            else
                echo "::warning::$BUNDLE_NAME signature verification failed"
            fi
        else
            echo "::warning::Failed to sign $BUNDLE_NAME"
        fi
    done
elif [ -n "$INPUT_SIGN_BUNDLES" ]; then
    echo "::warning::Bundle signing requested but no Application certificate available"
fi

# ============================================================================
# Sign the package
# ============================================================================

echo ""
echo "Signing package..."

# If output path differs from input, sign to new location; otherwise use temp file
if [ "$SIGNED_PKG" != "$INPUT_PACKAGE_PATH" ]; then
    if productsign --sign "$INSTALLER_IDENTITY" "$INPUT_PACKAGE_PATH" "$SIGNED_PKG"; then
        echo "  ✓ Package signed: $SIGNED_PKG"
    else
        echo "::error::Failed to sign package"
        exit 1
    fi
else
    TEMP_SIGNED="$INPUT_PACKAGE_PATH.signed"
    if productsign --sign "$INSTALLER_IDENTITY" "$INPUT_PACKAGE_PATH" "$TEMP_SIGNED"; then
        mv "$TEMP_SIGNED" "$SIGNED_PKG"
        echo "  ✓ Package signed: $SIGNED_PKG"
    else
        echo "::error::Failed to sign package"
        rm -f "$TEMP_SIGNED"
        exit 1
    fi
fi

# Verify package signature
if pkgutil --check-signature "$SIGNED_PKG" | grep -q "Developer ID Installer"; then
    echo "  ✓ Package signature verified"
    echo "signed=true" >> $GITHUB_OUTPUT
else
    echo "::error::Package signature verification failed"
    exit 1
fi

# ============================================================================
# Notarize (if credentials provided and not disabled)
# ============================================================================

CAN_NOTARIZE=false
if [ -n "$INPUT_APPLE_ID" ] && [ -n "$INPUT_APPLE_APP_PASSWORD" ] && [ -n "$INPUT_TEAM_ID" ]; then
    CAN_NOTARIZE=true
    echo "can_notarize=true" >> $GITHUB_OUTPUT
fi

SHOULD_NOTARIZE=false
if [ "$INPUT_NOTARIZE" = "true" ]; then
    SHOULD_NOTARIZE=true
elif [ "$INPUT_NOTARIZE" = "auto" ] && [ "$CAN_NOTARIZE" = true ]; then
    SHOULD_NOTARIZE=true
fi

if [ "$SHOULD_NOTARIZE" = true ]; then
    if [ "$CAN_NOTARIZE" = false ]; then
        echo "::warning::Notarization requested but credentials not provided"
    else
        echo ""
        echo "Submitting for notarization (this may take several minutes)..."
        
        if xcrun notarytool submit "$SIGNED_PKG" \
            --apple-id "$INPUT_APPLE_ID" \
            --password "$INPUT_APPLE_APP_PASSWORD" \
            --team-id "$INPUT_TEAM_ID" \
            --wait; then
            
            echo "  ✓ Notarization successful"
            echo "notarized=true" >> $GITHUB_OUTPUT
            
            # Staple the ticket
            echo "Stapling notarization ticket..."
            if xcrun stapler staple "$SIGNED_PKG"; then
                echo "  ✓ Ticket stapled"
                echo "stapled=true" >> $GITHUB_OUTPUT
            else
                echo "::warning::Failed to staple notarization ticket"
            fi
        else
            echo "::warning::Notarization failed — check xcrun notarytool log for details"
        fi
    fi
else
    echo ""
    echo "Skipping notarization (notarize=$INPUT_NOTARIZE, credentials_available=$CAN_NOTARIZE)"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "======================================"
echo "✓ Signing complete"
echo "  Package: $SIGNED_PKG"
echo "======================================"
