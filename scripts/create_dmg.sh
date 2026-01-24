#!/bin/bash
set -e

# ========================================
# SuperSay DMG Builder
# ========================================

APP_NAME="SuperSay"
VERSION="${1:-1.0.0}"
DMG_NAME="${APP_NAME}-${VERSION}"
BUILD_DIR="build"
# UPDATE: Path moved
XCODE_PROJECT_DIR="frontend/SuperSay"

echo "🚀 Building SuperSay v${VERSION} for Release..."

# Navigate to project root
cd "$(dirname "$0")/.."

# 0. Compile Backend
echo "🐍 Compiling Backend..."
./scripts/compile_backend.sh

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
    APP_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: Could not find ${APP_NAME}.app"
    exit 1
fi

echo "   ✓ Found app at: $APP_PATH"

# 3. Staging
STAGING_DIR="${BUILD_DIR}/dmg-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy the app
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Inject Fonts (Vital for correct Look & Feel)
echo "📦 Injecting Custom Fonts into DMG staging..."
mkdir -p "$STAGING_DIR/${APP_NAME}.app/Contents/Resources/Fonts"
cp frontend/SuperSay/SuperSay/Resources/Fonts/*.ttf "$STAGING_DIR/${APP_NAME}.app/Contents/Resources/Fonts/"

# 4. Create DMG (Standardized Check)
if command -v create-dmg &> /dev/null; then
    echo "🎨 Creating beautiful DMG with create-dmg..."
    rm -f "${BUILD_DIR}/${DMG_NAME}.dmg"
    
    # UPDATE: Icon path moved
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
    echo "📀 Creating DMG with hdiutil..."
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "$STAGING_DIR" \
        -ov -format UDZO \
        "${BUILD_DIR}/${DMG_NAME}.dmg"
fi

# 5. Cleanup
rm -rf "$STAGING_DIR"

echo "✅ DMG Created at ${BUILD_DIR}/${DMG_NAME}.dmg"
