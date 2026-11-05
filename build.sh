#!/bin/bash
# Builds Shelf.app and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/Shelf.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Shelf "$APP/Contents/MacOS/Shelf"

if [ ! -f build/Shelf.icns ]; then
  swift Resources/make-icon.swift build
  iconutil -c icns build/Shelf.iconset -o build/Shelf.icns
  rm -rf build/Shelf.iconset
fi
cp build/Shelf.icns "$APP/Contents/Resources/Shelf.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Shelf</string>
  <key>CFBundleDisplayName</key><string>Shelf</string>
  <key>CFBundleIdentifier</key><string>com.thomasflensted.shelf</string>
  <key>CFBundleExecutable</key><string>Shelf</string>
  <key>CFBundleIconFile</key><string>Shelf</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.books</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
mkdir -p ~/Applications
rm -rf ~/Applications/Shelf.app
cp -R "$APP" ~/Applications/Shelf.app
echo "Installed ~/Applications/Shelf.app"
