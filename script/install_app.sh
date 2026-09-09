#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="TypeInVoice"
PROJECT="$ROOT_DIR/TypeInVoice.xcodeproj"
SCHEME="TypeInVoice"
CONFIGURATION="Release"
DERIVED_DATA="${TYPE_IN_VOICE_DERIVED_DATA:-${TMPDIR:-/tmp}/TypeInVoice-InstallDerivedData}"
SOURCE_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
DEST_DIR="/Applications"
DEST_APP="$DEST_DIR/$APP_NAME.app"

if [[ ! -d "$PROJECT" ]]; then
  command -v xcodegen >/dev/null || {
    echo "xcodegen is required. Install it with: brew install xcodegen" >&2
    exit 1
  }
  xcodegen generate
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

mkdir -p "$DEST_DIR"
rm -rf "$DEST_APP"
/usr/bin/ditto "$SOURCE_APP" "$DEST_APP"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
/usr/bin/open -n "$DEST_APP"

cat <<EOF
Installed: $DEST_APP

For start-at-login:
1. Press Option+S in Type in Voice.
2. Enable "Launch at Login".
3. Grant Microphone and Accessibility permissions for this installed app if macOS prompts.
EOF
