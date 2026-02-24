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

echo "🚀 PHASE 2: Release Notes Extraction..."
# Extract section from CHANGELOG.md for this version
sed -n "/^### .*v$VERSION/,\${
    p
}" CHANGELOG.md > RELEASE_NOTES.all

# Only keep lines until the next version header
awk 'BEGIN {p=0} /^### .* v[0-9]/ {if(p) exit; p=1} p {print}' RELEASE_NOTES.all > RELEASE_NOTES.md
rm -f RELEASE_NOTES.all RELEASE_NOTES.tmp
rm -f RELEASE_NOTES.tmp

cat << EOF >> RELEASE_NOTES.md

## ⚠️ INSTALLATION NOTE (Gatekeeper)
Because this app is unsigned, macOS will flag it as damaged. Run this in Terminal:
\`\`\`bash
xattr -cr /Applications/SuperSay.app
\`\`\`
EOF

echo "🏷️ Tagging v$VERSION..."
git tag -a v$VERSION -F RELEASE_NOTES.md
git push origin v$VERSION

echo "🚀 PHASE 3: GitHub Release..."
gh release create v$VERSION "$DMG_PATH" \
    --title "$APP_NAME v$VERSION" \
    --notes-file RELEASE_NOTES.md

rm -f RELEASE_NOTES.md
echo "✅ SUCCESS! v$VERSION is live on GitHub."
