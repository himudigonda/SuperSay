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

.PHONY: all setup backend app run clean lint test test-backend test-swift test-ci format check-version release ship help

# Default: Run the full pipeline
all: run

# --- 🛠️ SETUP ---
setup:
	@echo "📦 Installing Python Dependencies..."
	cd backend && uv sync
	@echo "📦 Checking Swift Environment..."
	xcode-select -p || echo "⚠️ Xcode not found!"
	@echo "✅ Setup Complete."

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
		build
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

# --- 🔍 CODE QUALITY ---
lint:
	@echo "🧹 Linting Python..."
	cd backend && uv run ruff check .
	cd backend && uv run black --check .
	@echo "🧹 Linting Swift..."
	if which swiftlint >/dev/null; then swiftlint; else echo "⚠️ SwiftLint not installed"; fi

format:
	@echo "✨ Formatting Python..."
	cd backend && uv run ruff check --fix .
	cd backend && uv run black .
	@echo "✨ Formatting Swift..."
	if which swiftformat >/dev/null; then swiftformat . --swiftversion 6; else echo "⚠️ swiftformat not installed"; fi

# --- 📊 BENCHMARKS ---
benchmark:
	@mkdir -p backend/benchmarks
	@echo "🧪 Running Engine Scenarios..."
	cd backend && PYTHONPATH=. uv run python benchmarks/deep_profiler.py
	@echo "📈 Generating Visual Trends..."
	uv run python scripts/visualize_vitals.py
	@echo "📝 Generating Website Markdown Table..."
	uv run python scripts/generate_vitals_table.py

# --- 🧪 TESTS ---
# Everyday validation stays headless. The macOS host is explicit and serial so
# a test run cannot launch a pile of SuperSay instances or saturate the Mac.
test: test-backend

test-backend:
	@echo "🧪 Running fast backend tests (no macOS app launch)..."
	cd backend && uv run pytest -q

test-swift:
	@set -e; \
		lock="$(BUILD_DIR)/.swift-test.lock"; \
		mkdir -p "$(BUILD_DIR)"; \
		if ! mkdir "$$lock" 2>/dev/null; then \
			echo "A SuperSay Swift test run is already active. Wait for it to finish."; exit 2; \
		fi; \
		trap 'rmdir "$$lock"' EXIT; \
		if pgrep -f 'xcodebuild.*SuperSay.xcodeproj.*test' >/dev/null; then \
			echo "Another SuperSay xcodebuild test process is already active. Refusing to overlap it."; exit 2; \
		fi; \
		echo "🧪 Running one serial Swift test host..."; \
		xcodebuild test -project $(PROJECT_PATH) -scheme $(SCHEME) \
			-destination 'platform=macOS,arch=arm64' \
			-parallel-testing-enabled NO \
			CODE_SIGNING_ALLOWED=NO

test-ci: test-backend test-swift

# --- 📦 RELEASES ---
check-version:
ifndef VERSION
	$(error VERSION is required, e.g. `make release VERSION=2.0.1`)
endif

release: check-version backend
	@echo "🚀 Building the final legacy release for v$(VERSION) without touching local user data..."
	chmod +x scripts/create_dmg.sh
	./scripts/create_dmg.sh $(VERSION)
	@echo "✅ Release Ready: build/SuperSay-$(VERSION).dmg"

ship:
	@echo "SuperSay is archived. Automated publishing is intentionally disabled."
	@exit 1

help:
	@echo "SuperSay Management"
	@echo "  make clean     Wipe build artifacts"
	@echo "  make run       Build and launch fresh"
	@echo "  make release VERSION=2.0.1  Build the final legacy DMG without a user-data wipe"
	@echo "  make test      Run fast backend tests only"
	@echo "  make test-swift Run one serial macOS test host"
	@echo "  make test-ci   Run backend and serial macOS tests"
