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
mkdir -p "$bundle/Contents/Frameworks"

cp "$binary" "$bundle/Contents/MacOS/VibeKeyElements"
chmod +x "$bundle/Contents/MacOS/VibeKeyElements"

# Copy Sparkle.framework into App Bundle Frameworks directory
if [ -d "$bin_dir/Sparkle.framework" ]; then
  echo "==> Copying Sparkle.framework into App Bundle..."
  cp -R "$bin_dir/Sparkle.framework" "$bundle/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$bundle/Contents/MacOS/VibeKeyElements" 2>/dev/null || true
fi

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
    <key>NSHIDUsageDescription</key>
    <string>VibeKey Elements 需要输入监控来读取接收器上的按键、旋钮和设备事件。</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Patrick Fu. All rights reserved.</string>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/patrick-fu/vibekey-elements/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>xLcFpTMbuvJVcOJlZyap0OgZ2Tp8dJ1oC/BImxW2TaM=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>604800</integer>
    <key>SUAllowsAutomaticUpdates</key>
    <false/>
</dict>
</plist>
PLIST

sign_target() {
  local target="$1"
  if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "  Signing: $(basename "$target") with $DEVELOPER_ID"
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$target"
  else
    codesign --force --sign - "$target"
  fi
}

echo "==> Codesigning bundle components (inside-out)..."
SPARKLE_FW="$bundle/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
  # 1. Sign XPC services
  for xpc in "$SPARKLE_FW"/Versions/B/XPCServices/*.xpc; do
    if [ -d "$xpc" ]; then
      sign_target "$xpc"
    fi
  done
  # 2. Sign Autoupdate & Updater.app
  if [ -f "$SPARKLE_FW/Versions/B/Autoupdate" ]; then
    sign_target "$SPARKLE_FW/Versions/B/Autoupdate"
  fi
  if [ -d "$SPARKLE_FW/Versions/B/Updater.app" ]; then
    sign_target "$SPARKLE_FW/Versions/B/Updater.app"
  fi
  # 3. Sign Sparkle.framework
  sign_target "$SPARKLE_FW"
fi

# 4. Sign main binary
sign_target "$bundle/Contents/MacOS/VibeKeyElements"

# 5. Sign outer App bundle
echo "==> Signing App Bundle..."
sign_target "$bundle"

# 6. Sign CLI binary if present
if [ -f "$cli_binary" ]; then
  echo "==> Signing CLI binary..."
  sign_target "$cli_binary"
fi

echo "==> Successfully created: $bundle"
