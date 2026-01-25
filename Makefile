# ==========================================
# SuperSay Automation Pipeline
# ==========================================

# Configuration
PROJECT_PATH = frontend/SuperSay/SuperSay.xcodeproj
SCHEME = SuperSay
CONFIG = Release
BUILD_DIR = build
APP_PATH = $(BUILD_DIR)/DerivedData/Build/Products/$(CONFIG)/SuperSay.app

.PHONY: all setup backend app run clean lint test format

# Default: Run the full pipeline
all: run

# --- 🛠️ SETUP ---
setup:
	@echo "📦 Installing Python Dependencies..."
	cd backend && uv sync
	@echo "📦 Checking Swift Environment..."
	xcode-select -p || echo "⚠️ Xcode not found!"

# --- 🐍 BACKEND ---
backend:
	@echo "------------------------------------------------"
	@echo "🚀 [1/3] Building Python Backend..."
	@echo "------------------------------------------------"
	chmod +x scripts/compile_backend.sh
	./scripts/compile_backend.sh

# --- 🍎 FRONTEND ---
app:
	@echo "------------------------------------------------"
	@echo "🔨 [2/3] Building macOS Application..."
	@echo "------------------------------------------------"
	xcodebuild -project $(PROJECT_PATH) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR)/DerivedData \
		-quiet \
		clean build
	@echo "📦 Injecting Custom Fonts..."
	mkdir -p $(APP_PATH)/Contents/Resources/Fonts
	cp frontend/SuperSay/SuperSay/Resources/Fonts/*.ttf $(APP_PATH)/Contents/Resources/Fonts/
	@echo "✅ Build Successful: $(APP_PATH)"

# --- 🚀 LAUNCH ---
run: backend app
	@echo "------------------------------------------------"
	@echo "🎉 [3/3] Launching SuperSay..."
	@echo "------------------------------------------------"
	# Kill existing instance if running
	pkill -x "SuperSay" || true
	# Open the newly built app
	open $(APP_PATH)

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

# --- 🧪 TESTS ---

test: test-backend test-frontend
	@echo "✅ All tests passed."

test-backend:
	@echo "🧪 Testing Backend..."
	# Run pytest with the new test logic
	cd backend && uv run pytest -v

test-frontend:
	@echo "🧪 Testing Frontend..."
	# Standard Xcode test command to run all unit tests in the main scheme
	xcodebuild test \
		-project frontend/SuperSay/SuperSay.xcodeproj \
		-scheme SuperSay \
		-destination 'platform=macOS,arch=arm64' 
	@echo "⚠️ Frontend test execution relies on correctly configured XCTest targets in Xcode."

# --- 📦 RELEASES ---
release: clean
	@echo "🚀 Starting Full Release Build for v$(VERSION)..."
	chmod +x scripts/create_dmg.sh
	./scripts/create_dmg.sh $(VERSION)
	@echo "✅ Release Ready: build/SuperSay-$(VERSION).dmg"

# --- 🧹 UTILS ---
clean:
	@echo "🗑️ Cleaning artifacts..."
	rm -rf backend/dist backend/build
	rm -rf $(BUILD_DIR)
	rm -rf frontend/SuperSay/SuperSay/Resources/SuperSayServer

help:
	@echo "SuperSay Automation Hub"
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  setup           Install dependencies"
	@echo "  run             Build and launch app"
	@echo "  test            Run all test suites"
	@echo "  release VERSION=x.x.x  Build pretty DMG for distribution"
	@echo "  clean           Wipe build artifacts"
