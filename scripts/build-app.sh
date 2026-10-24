#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/dist}"
SCRATCH="${FILEORBIT_BUILD_DIR:-$ROOT/.build}"
VENDOR="${FILEORBIT_VENDOR_DIR:-$ROOT/.build/vendor}"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c release
BIN="$(swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c release --show-bin-path)"
# Stage outside cloud-backed Documents folders: File Provider can attach FinderInfo
# metadata to new app bundles there before codesign runs.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/fileorbit-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/FileOrbit.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp -X "$BIN/FileOrbit" "$APP/Contents/MacOS/FileOrbit"
cp -X "$BIN/fileorbit-cli" "$APP/Contents/MacOS/fileorbit-cli"
# Public binaries do not need debug symbols containing local source paths.
xcrun strip -S "$APP/Contents/MacOS/FileOrbit" "$APP/Contents/MacOS/fileorbit-cli"
cp -X "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -X "$ROOT/Resources/"*LICENSE* "$APP/Contents/Resources/"
cp -X "$ROOT/LICENSE" "$APP/Contents/Resources/FileOrbit-LICENSE.txt"
cp -X "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
if [[ -d "$ROOT/Resources/Licenses" ]]; then
    ditto --norsrc --noextattr "$ROOT/Resources/Licenses" "$APP/Contents/Resources/Licenses"
fi
if [[ -x "$VENDOR/qpdf/bin/qpdf" && -x "$VENDOR/resvg/resvg" ]]; then
    ditto --norsrc --noextattr "$VENDOR/qpdf" "$APP/Contents/Helpers/qpdf"
    cp -X "$VENDOR/resvg/resvg" "$APP/Contents/Helpers/resvg"
else
    echo "Bundled helpers absent; app will use installed qpdf/resvg if available." >&2
fi
if [[ -x "$VENDOR/cwebp/cwebp" ]]; then cp -X "$VENDOR/cwebp/cwebp" "$APP/Contents/Helpers/cwebp"; fi
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then cp -X "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"; fi
if [[ -d "$APP/Contents/Helpers/qpdf" ]]; then
    find "$APP/Contents/Helpers/qpdf" -type f \( -name '*.dylib' -o -perm -111 \) -exec codesign --force --sign - {} \;
fi
if [[ -f "$APP/Contents/Helpers/resvg" ]]; then codesign --force --sign - "$APP/Contents/Helpers/resvg"; fi
if [[ -f "$APP/Contents/Helpers/cwebp" ]]; then codesign --force --sign - "$APP/Contents/Helpers/cwebp"; fi
codesign --force --sign - "$APP/Contents/MacOS/fileorbit-cli"
codesign --force --sign - --entitlements "$ROOT/Resources/Entitlements.plist" "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$STAGE/FileOrbit-macOS-$(uname -m).zip"
if [[ -e "$DEST/FileOrbit.app" ]]; then
    OLD="$DEST/.FileOrbit.previous-$(date +%s).app"
    mv "$DEST/FileOrbit.app" "$OLD"
fi
mv "$APP" "$DEST/FileOrbit.app"
cp -X "$STAGE/FileOrbit-macOS-$(uname -m).zip" "$DEST/FileOrbit-macOS-$(uname -m).zip"
printf 'Built: %s\n' "$DEST/FileOrbit.app"
