#!/bin/bash
# Full Xcode owns App Intents metadata extraction and SwiftUI preview macros.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/.build/xcode}"
if ! xcrun --find appintentsmetadataprocessor >/dev/null 2>&1; then
    echo "Full Xcode is required for App Intents metadata. Select it with xcode-select, then rerun." >&2
    exit 2
fi
xcodebuild -project "$ROOT/FileOrbit.xcodeproj" -scheme FileOrbit -configuration Release \
    -derivedDataPath "$DEST" CODE_SIGNING_ALLOWED=NO build
APP="$DEST/Build/Products/Release/FileOrbit.app"
if [[ ! -d "$APP/Contents/Resources/Metadata.appintents" ]]; then
    echo "Xcode built the app but App Intents metadata was not emitted; do not claim Shortcuts registration." >&2
    exit 3
fi
printf 'Xcode app with App Intents metadata: %s\n' "$APP"
