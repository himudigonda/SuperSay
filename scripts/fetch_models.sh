#!/bin/bash
set -euo pipefail

# The public source tree intentionally excludes the 338 MB model assets.
# Keep the release build reproducible by fetching the exact upstream files and
# rejecting anything whose digest differs from the pinned legacy release.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSET_DIR="$ROOT_DIR/backend"
RELEASE_BASE="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"

fetch_asset() {
    local file="$1"
    local sha256="$2"
    local target="$ASSET_DIR/$file"
    local actual=""

    if [ -f "$target" ]; then
        actual="$(shasum -a 256 "$target" | awk '{print $1}')"
        if [ "$actual" = "$sha256" ]; then
            echo "✓ Verified $file"
            return
        fi
        echo "ERROR: $target exists but its SHA-256 does not match the pinned model." >&2
        echo "Delete that exact file and re-run this script to fetch a clean copy." >&2
        exit 1
    fi

    local temporary
    temporary="$(mktemp "$ASSET_DIR/.${file}.download.XXXXXX")"
    trap 'rm -f "$temporary"' RETURN
    echo "Downloading $file..."
    curl --fail --location --retry 3 --output "$temporary" "$RELEASE_BASE/$file"
    actual="$(shasum -a 256 "$temporary" | awk '{print $1}')"
    if [ "$actual" != "$sha256" ]; then
        echo "ERROR: digest mismatch for downloaded $file." >&2
        exit 1
    fi
    mv "$temporary" "$target"
    trap - RETURN
    echo "✓ Downloaded and verified $file"
}

fetch_asset "kokoro-v1.0.onnx" "7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5"
fetch_asset "voices-v1.0.bin" "bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d"
