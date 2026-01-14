# SerialTerm Makefile
# macOS Serial Terminal Application

.PHONY: all clean build-zig build-swift build run package install help

# Configuration
APP_NAME = SerialTerm
BUNDLE_ID = com.serialterm.app
VERSION = 0.1.0

BUILD_DIR = build
ZIG_OUT = zig-out
DERIVED_DATA = $(BUILD_DIR)/DerivedData

# Zig configuration
ZIG = zig
ZIG_TARGET_ARM = aarch64-macos
ZIG_TARGET_X86 = x86_64-macos
ZIG_OPTIMIZE = ReleaseFast

# Xcode configuration
XCODE_PROJECT = macos/SerialTerm.xcodeproj
XCODE_SCHEME = SerialTerm
XCODE_CONFIG = Release

# Default target
all: build

# Help
help:
	@echo "SerialTerm Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build everything (default)"
	@echo "  build        - Build the application"
	@echo "  build-zig    - Build only the Zig library"
	@echo "  build-swift  - Build only the Swift app"
	@echo "  run          - Build and run the application"
	@echo "  clean        - Clean all build artifacts"
	@echo "  package      - Create DMG installer"
	@echo "  install      - Install to /Applications"
	@echo "  test         - Run tests"
	@echo ""
	@echo "Configuration:"
	@echo "  VERSION      = $(VERSION)"
	@echo "  ZIG_OPTIMIZE = $(ZIG_OPTIMIZE)"
	@echo "  XCODE_CONFIG = $(XCODE_CONFIG)"

# Build Zig library
build-zig:
	@echo "Building Zig library..."
	$(ZIG) build -Doptimize=$(ZIG_OPTIMIZE)
	@echo "Zig library built successfully"

# Build Swift application
build-swift: build-zig
	@echo "Building Swift application..."
	@mkdir -p $(BUILD_DIR)
	swift build -c release \
		--package-path macos \
		--build-path $(BUILD_DIR)/swift
	@echo "Swift application built successfully"

# Build everything (using swift build for simplicity)
build: build-swift
	@echo "Build complete!"

# Run the application
run: build
	@echo "Running SerialTerm..."
	@if [ -d "$(BUILD_DIR)/swift/release/$(APP_NAME).app" ]; then \
		open "$(BUILD_DIR)/swift/release/$(APP_NAME).app"; \
	else \
		swift run --package-path macos --build-path $(BUILD_DIR)/swift; \
	fi

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	rm -rf $(ZIG_OUT)
	rm -rf .zig-cache
	rm -rf macos/.build
	rm -rf $(APP_NAME).dmg
	@echo "Clean complete"

# Run tests
test: test-zig test-swift

test-zig:
	@echo "Running Zig tests..."
	$(ZIG) build test

test-swift:
	@echo "Running Swift tests..."
	swift test --package-path macos --build-path $(BUILD_DIR)/swift

# Create DMG package
package: build
	@echo "Creating DMG package..."
	@mkdir -p $(BUILD_DIR)/dmg
	@if [ -d "$(BUILD_DIR)/swift/release/$(APP_NAME).app" ]; then \
		cp -R "$(BUILD_DIR)/swift/release/$(APP_NAME).app" "$(BUILD_DIR)/dmg/"; \
	fi
	@ln -sf /Applications "$(BUILD_DIR)/dmg/Applications"
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder "$(BUILD_DIR)/dmg" \
		-ov -format UDZO \
		"$(APP_NAME)-$(VERSION).dmg"
	@rm -rf $(BUILD_DIR)/dmg
	@echo "DMG created: $(APP_NAME)-$(VERSION).dmg"

# Install to Applications
install: build
	@echo "Installing to /Applications..."
	@if [ -d "$(BUILD_DIR)/swift/release/$(APP_NAME).app" ]; then \
		sudo cp -R "$(BUILD_DIR)/swift/release/$(APP_NAME).app" /Applications/; \
		echo "Installed to /Applications/$(APP_NAME).app"; \
	else \
		echo "Error: Application not found"; \
		exit 1; \
	fi

# Development helpers
dev: build-zig
	@echo "Development build ready"
	@echo "Run 'make run' to launch the application"

# Format code
format:
	@echo "Formatting Zig code..."
	$(ZIG) fmt src/
	@echo "Formatting Swift code..."
	swift-format -i -r macos/SerialTerm/

# Lint code
lint:
	@echo "Linting Zig code..."
	$(ZIG) fmt --check src/
	@echo "Linting Swift code..."
	swift-format lint -r macos/SerialTerm/
