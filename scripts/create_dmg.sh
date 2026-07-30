#!/bin/bash
set -euo pipefail

# ========================================
# SuperSay DMG Builder
# ========================================
APP_NAME="SuperSay"
VERSION="${1:-2.0.1}"
DMG_NAME="${APP_NAME}-${VERSION}"
BUILD_DIR="build"
XCODE_PROJECT_DIR="frontend/SuperSay"
STAGING_DIR="${BUILD_DIR}/dmg-staging"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"
# Keep release archiving bounded on a developer machine. Override explicitly
# only when the machine is reserved for a release build.
XCODE_JOBS="${XCODE_JOBS:-4}"

# Locate Xcode: prefer full Xcode.app over CommandLineTools so xcodebuild works.
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
elif [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
else
    echo "⚠️  Full Xcode.app not found at /Applications/Xcode.app — trying system default."
    echo "   If this fails, install Xcode from the App Store and re-run."
fi

echo "🔧 Using developer dir: ${DEVELOPER_DIR:-system default}"
echo "🚀 Building SuperSay v${VERSION} Professional DMG..."

# 1. Archive and Export App (Ensuring it's the Release build)
# A release archive must not reuse an app bundle left by an earlier build.
rm -rf "${BUILD_DIR}/${APP_NAME}.xcarchive"
xcodebuild -project "${XCODE_PROJECT_DIR}/SuperSay.xcodeproj" \
    -scheme "SuperSay" \
    -configuration Release \
    -jobs "$XCODE_JOBS" \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    MARKETING_VERSION="${VERSION}" \
    archive \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    AD_HOC_CODE_SIGNING_ALLOWED=YES

# 2. Export the app from the Archive
echo "📦 Exporting app from Archive..."
APP_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: App not found at $APP_PATH"
    exit 1
fi

echo "   ✓ Found app at: $APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
echo "   ✓ Archived app signature is structurally valid."

# 3. Setup Staging
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

# 3. Inject Backend & Fonts
mkdir -p "$STAGING_DIR/${APP_NAME}.app/Contents/Resources/Fonts"
cp frontend/SuperSay/SuperSay/Resources/Fonts/*.ttf "$STAGING_DIR/${APP_NAME}.app/Contents/Resources/Fonts/"
cp frontend/SuperSay/SuperSay/Resources/SuperSayServer.zip "$STAGING_DIR/${APP_NAME}.app/Contents/Resources/"

# These resources are injected after Xcode archives the app. Refresh the
# top-level seal so the distributed bundle is valid, not merely the archive.
STAGED_APP="$STAGING_DIR/${APP_NAME}.app"
codesign --force --sign "$SIGNING_IDENTITY" \
    --preserve-metadata=identifier,entitlements,requirements,flags,runtime \
    "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
echo "   ✓ Final staged app signature seals bundled resources."

# 4. Create the Professional DMG
# Note: We use the App Icon as the Volume Icon
rm -f "${BUILD_DIR}/${DMG_NAME}.dmg"

if command -v create-dmg &> /dev/null; then
    create-dmg \
        --volname "${APP_NAME}" \
        --volicon "${XCODE_PROJECT_DIR}/SuperSay/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 180 190 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 480 190 \
        --no-internet-enable \
        "${BUILD_DIR}/${DMG_NAME}.dmg" \
        "$STAGING_DIR" || {
            echo "⚠️ create-dmg failed, falling back to hdiutil..."
            hdiutil create -volname "${APP_NAME}" \
                -srcfolder "$STAGING_DIR" \
                -ov -format UDZO \
                "${BUILD_DIR}/${DMG_NAME}.dmg"
        }
else
    echo "📀 Creating DMG with hdiutil..."
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "$STAGING_DIR" \
        -ov -format UDZO \
        "${BUILD_DIR}/${DMG_NAME}.dmg"
fi

# 5. Cleanup
rm -rf "$STAGING_DIR"

echo "✅ DMG Created at ${BUILD_DIR}/${DMG_NAME}.dmg"
