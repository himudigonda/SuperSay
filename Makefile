# ==========================================
# SuperSay Automation Pipeline
# ==========================================

.PHONY: all setup lint test build-backend build-app run clean

# Default: Setup and Build everything
all: setup build-backend build-app

# --- 🛠️ SETUP & INSTALLATION ---
setup:
	@echo "📦 Installing Python Dependencies..."
	cd backend && uv sync
	@echo "📦 Checking Swift Environment..."
	xcode-select -p || echo "⚠️ Xcode not found!"

# --- 🔍 CODE QUALITY ---
lint:
	@echo "🧹 Linting Python..."
	cd backend && uv run ruff check .
	cd backend && uv run black --check .
	@echo "🧹 Linting Swift (Requires SwiftLint)..."
	if which swiftlint >/dev/null; then swiftlint; else echo "⚠️ SwiftLint not installed (brew install swiftlint)"; fi

format:
	@echo "✨ Formatting Python..."
	cd backend && uv run black .

test:
	@echo "🧪 Testing Backend..."
	cd backend && uv run pytest

# --- 🏗️ BUILD PIPELINE ---
build-backend:
	@echo "🔨 Compiling Python Backend..."
	./scripts/compile_backend.sh

build-app:
	@echo "🔨 Building macOS Application..."
	# This builds the app and puts it in build/
	xcodebuild -project frontend/SuperSay/SuperSay.xcodeproj \
		-scheme SuperSay \
		-configuration Release \
		-derivedDataPath build/DerivedData \
		clean build

dmg: build-backend
	@echo "💿 Creating Installer..."
	./scripts/create_dmg.sh 1.0.0

# --- 🚀 RUNNING ---
run:
	@echo "🚀 Launching SuperSay..."
	open frontend/SuperSay/SuperSay.xcodeproj

# --- 🗑️ CLEANUP ---
clean:
	@echo "🗑️ Cleaning artifacts..."
	rm -rf backend/dist backend/build
	rm -rf build/
	rm -rf frontend/SuperSay/SuperSay/Resources/SuperSayServer
