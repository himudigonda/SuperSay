#!/bin/bash
set -e

# Usage: ./scripts/ship.sh 1.0.6
VERSION=$1

if [ -z "$VERSION" ]; then
    echo "❌ Error: No version specified."
    exit 1
fi

APP_NAME="SuperSay"
DMG_PATH="build/SuperSay-${VERSION}.dmg"

echo "🚢 STARTING DISTRIBUTION FOR V$VERSION"

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ Error: DMG not found at $DMG_PATH. Did the build fail?"
    exit 1
fi

echo "🏷️ PHASE 1: Git Hygiene & Tagging..."
# Clean up existing local/remote tags if re-running
git tag -d v$VERSION 2>/dev/null || true
git push origin --delete v$VERSION 2>/dev/null || true

git add .
git commit -m "chore: release v$VERSION" || true
git push origin main

git tag -a v$VERSION -m "$APP_NAME v$VERSION: Definitive Edition"
git push origin v$VERSION

echo "🚀 PHASE 2: GitHub Release..."
# Extract section from CHANGELOG.md for this version
# This finds the line with the version and reads until the next version header
sed -n "/## \[$VERSION\]/,/## \[/p" CHANGELOG.md | sed '$d' > RELEASE_NOTES.md

cat << EOF >> RELEASE_NOTES.md

## ⚠️ INSTALLATION NOTE (Gatekeeper)
Because this app is unsigned, macOS will flag it as damaged. Run this in Terminal:
\`\`\`bash
xattr -cr /Applications/SuperSay.app
\`\`\`
EOF

gh release create v$VERSION "$DMG_PATH" \
    --title "$APP_NAME v$VERSION" \
    --notes-file RELEASE_NOTES.md

rm RELEASE_NOTES.md
echo "✅ SUCCESS! v$VERSION is live on GitHub."
