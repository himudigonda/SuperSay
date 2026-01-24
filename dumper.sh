#!/bin/bash

# SuperSay Code Dumper
# Recursively prints file names and contents, excluding non-code files

echo "========================================"
echo "  SuperSay Project Code Dump"
echo "  Generated: $(date)"
echo "========================================"
echo ""

# Find and print all relevant code files
find . -type f \
    ! -path '*/.git/*' \
    ! -path '*/.venv/*' \
    ! -path '*/node_modules/*' \
    ! -path '*/__pycache__/*' \
    ! -path '*/.DS_Store' \
    ! -path '*.pyc' \
    ! -path '*.pyo' \
    ! -path '*.onnx' \
    ! -path '*.bin' \
    ! -path '*.lock' \
    ! -path '*uv.lock' \
    ! -path '*.xcuserstate' \
    ! -path '*/xcuserdata/*' \
    ! -path '*/DerivedData/*' \
    ! -path '*/.build/*' \
    ! -path '*.app/*' \
    ! -name '.DS_Store' \
    ! -name '*.png' \
    ! -name '*.jpg' \
    ! -name '*.jpeg' \
    ! -name '*.gif' \
    ! -name '*.ico' \
    ! -name '*.icns' \
    ! -name '*.wav' \
    ! -name '*.mp3' \
    ! -name 'Package.resolved' \
    | sort \
    | while read -r file; do
        echo ""
        echo "========================================"
        echo "FILE: $file"
        echo "========================================"
        cat "$file"
        echo ""
    done

echo ""
echo "========================================"
echo "  End of Code Dump"
echo "========================================"
