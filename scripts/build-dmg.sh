#!/bin/bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

build_dir="$root/.build/release"
bundle="$build_dir/VibeKey Elements.app"
dmg_dir="$root/dist"
dmg_path="$dmg_dir/VibeKey-Elements-macOS-arm64.dmg"

# Ensure app bundle exists
if [ ! -d "$bundle" ]; then
  "$root/scripts/build-app.sh" arm64
fi

mkdir -p "$dmg_dir"
rm -f "$dmg_path" 2>/dev/null || true

stage="$(mktemp -d "${TMPDIR:-/tmp}/vibekey-dmg.XXXXXX")"
trap 'python3 -c "import shutil, os; os.path.exists(\"$stage\") and shutil.rmtree(\"$stage\")"' EXIT HUP INT TERM

echo "==> Staging files for DMG at: $stage"
cp -R "$bundle" "$stage/VibeKey Elements.app"
ln -s /Applications "$stage/Applications"

# Copy CLI tool alongside for convenience if present
bin_dir="$(swift build -c release --show-bin-path --arch arm64)"
if [ -f "$bin_dir/vibekey" ]; then
  cp "$bin_dir/vibekey" "$stage/vibekey"
  chmod +x "$stage/vibekey"
fi

echo "==> Creating compressed DMG: $dmg_path"
/usr/bin/hdiutil create -format UDZO -ov -volname "VibeKey Elements" -srcfolder "$stage" "$dmg_path"

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "==> Signing DMG with identity: $DEVELOPER_ID"
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$dmg_path"
fi

echo "==> Successfully created: $dmg_path"
