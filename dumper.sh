#!/bin/bash

# SuperSay Code Dumper
# Optimized for high-signal code reviews, focusing purely on logic and configuration.

echo "========================================"
echo "  SuperSay Project Code Dump"
echo "  Generated: $(date)"
echo "========================================"
echo ""

echo "PROJECT TREE (High-Level):"
echo "----------------------------------------"
# Show directory structure up to 3 levels deep, ignoring noise
tree -L 3 -a -I ".git|.venv|node_modules|__pycache__|build|dist|DerivedData|.build|.gemini|.agent|*.xcassets|*.xcodeproj|*.xcworkspace|*.app|*.dmg|*.xcarchive|*.pcm|*.wav|*.onnx|*.bin"
echo "----------------------------------------"
echo ""

# Initialize stats
total_files=0
total_lines=0
total_words=0
total_chars=0

# Find and print all relevant code files
# We focus on Swift, Python, Shell, Makefile, and Config files
# We explicitly exclude binary files, assets, and auto-generated lock files
while read -r file; do
    # Final check to avoid binary files that might have snuck in via extension
    if [[ "$(file -b --mime-encoding "$file")" == "binary" ]]; then
        continue
    fi

    echo ""
    echo "========================================"
    echo "FILE: $file"
    echo "========================================"
    cat "$file"
    echo ""

    # Update stats
    file_stats=($(wc "$file"))
    total_lines=$((total_lines + file_stats[0]))
    total_words=$((total_words + file_stats[1]))
    total_chars=$((total_chars + file_stats[2]))
    total_files=$((total_files + 1))

done < <(find . -type f \
    \( \
        -name "*.swift" -o \
        -name "*.py" -o \
        -name "*.sh" -o \
        -name "Makefile" -o \
        -name "*.toml" -o \
        -name "*.yaml" -o \
        -name "*.yml" -o \
        -name "*.md" \
    \) \
    ! -path "*/.git/*" \
    ! -path "*/.venv/*" \
    ! -path "*/node_modules/*" \
    ! -path "*/__pycache__/*" \
    ! -path "*/.DS_Store" \
    ! -path "*/xcuserdata/*" \
    ! -path "*/DerivedData/*" \
    ! -path "*/.build/*" \
    ! -path "*/build/*" \
    ! -path "*/dist/*" \
    ! -path "*/.gemini/*" \
    ! -path "*/.agent/*" \
    ! -path "*/*.xcassets/*" \
    ! -path "*/*.xcodeproj/*" \
    ! -path "*/*.xcworkspace/*" \
    ! -name "uv.lock" \
    ! -name "Package.resolved" \
    | sort)

echo ""
echo "========================================"
echo "  CODE STATISTICS"
echo "========================================"
echo "  Total Files:      $total_files"
echo "  Total Lines:      $total_lines"
echo "  Total Words:      $total_words"
echo "  Total Characters: $total_chars"
echo "========================================"
echo ""
echo "========================================"
echo "  End of Code Dump"
echo "========================================"
