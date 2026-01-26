# ==========================================
# SuperSay Automation Pipeline
# ==========================================

# Configuration
PROJECT_PATH = frontend/SuperSay/SuperSay.xcodeproj
SCHEME = SuperSay
CONFIG = Release
BUILD_DIR = build
APP_PATH = $(BUILD_DIR)/DerivedData/Build/Products/$(CONFIG)/SuperSay.app
BUNDLE_ID = com.himudigonda.SuperSay

.PHONY: all setup backend app run clean nuke lint test format

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
	pkill -x "SuperSay" || true
	open $(APP_PATH)

# --- 🧹 UTILS (The Nuking Zone) ---

# Standard clean: Wipes all local build artifacts
clean:
	@echo "🗑️ Cleaning local artifacts..."
	rm -rf backend/dist backend/build
	rm -rf $(BUILD_DIR)
	rm -rf frontend/SuperSay/DerivedData
	rm -rf frontend/SuperSay/SuperSay/Resources/SuperSayServer
	rm -rf frontend/SuperSay/SuperSay/Resources/SuperSayServer.zip
	find . -name "__pycache__" -type d -exec rm -rf {} +
	@echo "✨ Local build folders cleared."

# The Full Nuke: clean + system-level wipe + permission reset
nuke: clean
	@echo "🧨 NUKING SYSTEM DATA..."
	pkill -9 "SuperSay" || true
	pkill -9 "SuperSayServer" || true
	rm -rf ~/Library/Application\ Support/SuperSayServer
	rm -rf ~/Library/Application\ Support/$(BUNDLE_ID)
	@echo "🔐 Resetting macOS Accessibility Database..."
	tccutil reset Accessibility $(BUNDLE_ID) || true
	@echo "✅ Factory reset complete. Run 'make run' for a truly fresh start."

# --- 🔍 CODE QUALITY ---
lint:
	@echo "🧹 Linting Python..."
	cd backend && uv run ruff check .
	cd backend && uv run black --check .
	@echo "🧹 Linting Swift..."
	if which swiftlint >/dev/null; then swiftlint; else echo "⚠️ SwiftLint not installed"; fi

format:
	@echo "✨ Formatting Python..."
	cd backend && uv run black .

# --- 🧪 TESTS ---
test:
	@echo "🧪 Testing Backend..."
	cd backend && uv run pytest -v
	@echo "🧪 Testing Frontend..."
	xcodebuild test -project $(PROJECT_PATH) -scheme $(SCHEME) -destination 'platform=macOS,arch=arm64'

# --- 📦 RELEASES ---
release: nuke
	@echo "🚀 Starting Full Release Build for v$(VERSION)..."
	chmod +x scripts/create_dmg.sh
	./scripts/create_dmg.sh $(VERSION)
	@echo "✅ Release Ready: build/SuperSay-$(VERSION).dmg"

help:
	@echo "SuperSay Management"
	@echo "  make clean     Wipe build artifacts"
	@echo "  make nuke      Complete factory reset (removes permissions/app data)"
	@echo "  make run       Build and launch fresh"
	@echo "  make release   Nuke, rebuild, and create distribution DMG"
	@echo "  make test      Run all test suites"
