APP_NAME = VoiceInput
BUNDLE_ID = com.voiceinput.app
SIGN_ID = -
ENTITLEMENTS = Entitlements/VoiceInput.entitlements

.PHONY: build run install clean sign dev

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