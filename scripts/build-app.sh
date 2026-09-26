#!/bin/bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

arch="${1:-arm64}"
build_dir="$root/.build"
bundle="$build_dir/release/VibeKey Elements.app"

echo "==> Building VibeKey Elements for architecture: $arch"
swift build -c release --arch "$arch"

bin_dir="$(swift build -c release --show-bin-path --arch "$arch")"
binary="$bin_dir/VibeKeyElements"
cli_binary="$bin_dir/vibekey"

if [ ! -f "$binary" ]; then
  echo "Error: Binary not found at $binary" >&2
  exit 1
fi

echo "==> Constructing App Bundle at: $bundle"
rm -rf "$bundle" 2>/dev/null || python3 -c "import shutil, os; os.path.exists('$bundle') and shutil.rmtree('$bundle')"
mkdir -p "$bundle/Contents/MacOS"
mkdir -p "$bundle/Contents/Resources"

cp "$binary" "$bundle/Contents/MacOS/VibeKeyElements"
chmod +x "$bundle/Contents/MacOS/VibeKeyElements"

cat << 'PLIST' > "$bundle/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VibeKeyElements</string>
    <key>CFBundleIdentifier</key>
    <string>com.patrickfu.VibeKeyElements</string>
    <key>CFBundleName</key>
    <string>VibeKey Elements</string>
    <key>CFBundleDisplayName</key>
    <string>VibeKey Elements</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.1</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Patrick Fu. All rights reserved.</string>
</dict>
</plist>
PLIST

# Optional Developer ID codesign if signing identity is provided
if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "==> Signing App Bundle with identity: $DEVELOPER_ID"
  codesign --force --deep --options runtime --timestamp \
    --sign "$DEVELOPER_ID" "$bundle"
  
  if [ -f "$cli_binary" ]; then
    echo "==> Signing CLI binary with identity: $DEVELOPER_ID"
    codesign --force --options runtime --timestamp \
      --sign "$DEVELOPER_ID" "$cli_binary"
  fi
fi

echo "==> Successfully created: $bundle"
