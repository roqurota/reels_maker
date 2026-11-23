#!/bin/zsh
# Builds Reels Studio.app into ./build (release, ad-hoc signed).
set -e
cd "$(dirname "$0")"
swift build -c release
APP="build/Reels Studio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ReelsStudio "$APP/Contents/MacOS/ReelsStudio"
# icon: redraw with `swift scripts/make-icon.swift Resources/icon_1024.png` and rebuild the .icns if changed
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Reels Studio</string>
  <key>CFBundleDisplayName</key><string>Reels Studio</string>
  <key>CFBundleIdentifier</key><string>band.thelastroman.reelsstudio</string>
  <key>CFBundleExecutable</key><string>ReelsStudio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built: $(pwd)/$APP"
