#!/bin/bash
# Dual packaging: this script builds the macOS app via SPM (`swift build`).
# iOS app = Xcode monorepo only (`create_xcodeproj.py` + Simulator/xcodebuild).
# Declared Package.swift iOS platform does not make host `swift test` typecheck iOS #if.

# Exit on error
set -e

echo "=== Building DeveloperChatbot Executable ==="
swift build -c release

echo "=== Creating macOS App Bundle structure ==="
APP_DIR="release/DeveloperChatbot.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

# Clean previous release bundle
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "=== Copying built executable ==="
cp ".build/release/DeveloperChatbot" "$MACOS_DIR/DeveloperChatbot"

echo "=== Generating Info.plist ==="
cat <<EOF > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DeveloperChatbot</string>
    <key>CFBundleIdentifier</key>
    <string>com.developer.DeveloperChatbot</string>
    <key>CFBundleName</key>
    <string>DeveloperChatbot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>This app needs access to your microphone to transcribe your speech into text for the chatbot.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "=== App Bundle created successfully at $APP_DIR ==="
echo "You can now run: open $APP_DIR"
