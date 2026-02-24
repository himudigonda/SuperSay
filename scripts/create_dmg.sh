#!/bin/bash
set -e

# ========================================
# SuperSay DMG Builder
# ========================================
APP_NAME="SuperSay"
VERSION="${1:-1.0.6}"
DMG_NAME="${APP_NAME}-${VERSION}"
BUILD_DIR="build"
XCODE_PROJECT_DIR="frontend/SuperSay"
STAGING_DIR="${BUILD_DIR}/dmg-staging"

echo "🚀 Building SuperSay v${VERSION} Professional DMG..."

# 1. Archive and Export App (Ensuring it's the Release build)
xcodebuild -project "${XCODE_PROJECT_DIR}/SuperSay.xcodeproj" \
    -scheme "SuperSay" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    MARKETING_VERSION="${VERSION}" \
    archive \
    CODE_SIGN_IDENTITY="-" \
    AD_HOC_CODE_SIGNING_ALLOWED=YES

# 2. Export the app from the Archive
echo "📦 Exporting app from Archive..."
APP_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: App not found at $APP_PATH"
    exit 1
fi

echo "   ✓ Found app at: $APP_PATH"

# 3. Setup Staging
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

# 3. Inject Backend & Fonts
mkdir -p "$STAGING_DIR/${APP_NAME}.app/Contents/Resources/Fonts"
cp frontend/SuperSay/SuperSay/Resources/Fonts/*.ttf "$STAGING_DIR/${APP_NAME}.app/Contents/Resources/Fonts/"
cp frontend/SuperSay/SuperSay/Resources/SuperSayServer.zip "$STAGING_DIR/${APP_NAME}.app/Contents/Resources/"

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
