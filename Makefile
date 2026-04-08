APP_NAME = VoiceInput
BUNDLE_ID = com.voiceinput.app
SIGN_ID = -
ENTITLEMENTS = Entitlements/VoiceInput.entitlements
VERSION = 1.0.0
DMG_NAME = $(APP_NAME)-$(VERSION).dmg

.PHONY: build run install clean sign dev dmg

build:
	@echo "Building VoiceInput..."
	swift build -c release
	@echo "Creating app bundle..."
	mkdir -p build/Release/$(APP_NAME).app/Contents/MacOS
	mkdir -p build/Release/$(APP_NAME).app/Contents/Resources
	cp .build/arm64-apple-macosx/release/$(APP_NAME) build/Release/$(APP_NAME).app/Contents/MacOS/
	cp Resources/Info.plist build/Release/$(APP_NAME).app/Contents/
	@echo "Build complete: build/Release/$(APP_NAME).app"

run:
	open build/Release/$(APP_NAME).app

install:
	@echo "Installing to /Applications..."
	cp -r build/Release/$(APP_NAME).app /Applications/
	@echo "Installed. Run from Applications folder or Spotlight."

clean:
	rm -rf build
	swift package clean

sign:
	@echo "Signing app bundle with entitlements..."
	codesign --force --deep --sign $(SIGN_ID) --entitlements $(ENTITLEMENTS) build/Release/$(APP_NAME).app
	@echo "Signed."

# Development build (faster, no optimization)
dev:
	swift build
	mkdir -p build/Debug/$(APP_NAME).app/Contents/MacOS
	mkdir -p build/Debug/$(APP_NAME).app/Contents/Resources
	cp .build/arm64-apple-macosx/debug/$(APP_NAME) build/Debug/$(APP_NAME).app/Contents/MacOS/
	cp Resources/Info.plist build/Debug/$(APP_NAME).app/Contents/
	@echo "Dev build: build/Debug/$(APP_NAME).app"

# Create DMG installer
dmg: build sign
	@echo "Creating DMG installer..."
	@# Clean previous DMG build
	rm -rf build/dmg
	mkdir -p build/dmg
	@# Copy app to DMG folder
	cp -R build/Release/$(APP_NAME).app build/dmg/
	@# Create Applications symlink
	ln -s /Applications build/dmg/Applications
	@# Remove old DMG if exists
	rm -f build/$(DMG_NAME)
	@# Create DMG using hdiutil
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder build/dmg \
		-ov -format UDZO \
		-imagekey zlib-level=9 \
		build/$(DMG_NAME)
	@# Clean up
	rm -rf build/dmg
	@echo ""
	@echo "DMG created: build/$(DMG_NAME)"
	@echo "Size: $$(du -h build/$(DMG_NAME) | cut -f1)"

# Build, sign, and create DMG in one step
release: dmg
	@echo "Release build complete!"