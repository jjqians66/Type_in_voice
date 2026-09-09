#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/TypeInVoice.xcodeproj"
DERIVED_DATA="${TYPE_IN_VOICE_DERIVED_DATA:-${TMPDIR:-/tmp}/TypeInVoice-PackageDerivedData}"
APP_PATH="$DERIVED_DATA/Build/Products/Release/TypeInVoice.app"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/TypeInVoice-macOS-universal.dmg"
ZIP_PATH="$DIST_DIR/TypeInVoice-macOS-universal.zip"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/TypeInVoice-DMG.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

command -v xcodegen >/dev/null || {
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 1
}

cd "$ROOT_DIR"
xcodegen generate

xcodebuild \
  -project "$PROJECT" \
  -scheme TypeInVoice \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  build

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH" "$ZIP_PATH"
/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/TypeInVoice.app"
ln -s /Applications "$STAGING_DIR/Applications"

/usr/bin/hdiutil create \
  -volname "Type in Voice" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Created:"
echo "  $DMG_PATH"
echo "  $ZIP_PATH"
