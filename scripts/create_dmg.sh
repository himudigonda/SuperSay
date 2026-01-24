#!/bin/bash
set -e

# ========================================
# SuperSay DMG Builder
# Creates a beautiful, distributable DMG
# ========================================

APP_NAME="SuperSay"
VERSION="${1:-1.0.0}"
DMG_NAME="${APP_NAME}-${VERSION}"
BUILD_DIR="build"
XCODE_PROJECT_DIR="SuperSay"

echo "🚀 Building SuperSay v${VERSION} for Release..."

# Navigate to project root
cd "$(dirname "$0")/.."

# 1. Build the Release app bundle
echo "🔨 Building Release configuration..."
xcodebuild -project "${XCODE_PROJECT_DIR}/SuperSay.xcodeproj" \
    -scheme "SuperSay" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    archive \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

# 2. Export the app
echo "📦 Exporting app bundle..."
APP_PATH="${BUILD_DIR}/DerivedData/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    # Try archive path
    APP_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: Could not find ${APP_NAME}.app"
    echo "   Checked: ${BUILD_DIR}/DerivedData/Build/Products/Release/${APP_NAME}.app"
    echo "   Checked: ${BUILD_DIR}/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app"
    exit 1
fi

echo "   ✓ Found app at: $APP_PATH"

# 3. Create a staging directory
STAGING_DIR="${BUILD_DIR}/dmg-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy the app
cp -R "$APP_PATH" "$STAGING_DIR/"

# Create a symbolic link to Applications
ln -s /Applications "$STAGING_DIR/Applications"

# 4. Check if create-dmg is installed
if command -v create-dmg &> /dev/null; then
    echo "🎨 Creating beautiful DMG with create-dmg..."
    
    rm -f "${BUILD_DIR}/${DMG_NAME}.dmg"
    
    create-dmg \
        --volname "${APP_NAME}" \
        --volicon "${XCODE_PROJECT_DIR}/SuperSay/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" \
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
    echo "📀 Creating DMG with hdiutil (install 'create-dmg' for prettier results)..."
    echo "   Install with: brew install create-dmg"
    
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "$STAGING_DIR" \
        -ov -format UDZO \
        "${BUILD_DIR}/${DMG_NAME}.dmg"
fi

# 5. Cleanup
rm -rf "$STAGING_DIR"

# 6. Get final size
DMG_PATH="${BUILD_DIR}/${DMG_NAME}.dmg"
if [ -f "$DMG_PATH" ]; then
    DMG_SIZE=$(ls -lh "$DMG_PATH" | awk '{print $5}')
    echo ""
    echo "✅ DMG Created Successfully!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📍 Location: $(pwd)/${DMG_PATH}"
    echo "📦 Size: ${DMG_SIZE}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🎉 Ready to upload to GitHub Releases!"
else
    echo "❌ Error: DMG creation failed"
    exit 1
fi
