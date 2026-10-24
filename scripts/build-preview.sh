#!/bin/bash
# Build an isolated local UI preview without touching an installed FileOrbit.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
DEST="${1:-$ROOT/dist/preview}"
NAME="FileOrbit Preview.app"
ARCHIVE="FileOrbit-Glass-Preview-macOS-$(uname -m).zip"

# Resolve existing symlinks and normalize missing path components without
# creating anything. A simple `cd` cannot resolve a not-yet-created destination.
canonical_destination() {
    local remaining="$1" resolved component candidate
    if [[ "$remaining" == /* ]]; then resolved="/"; else resolved="$(pwd -P)"; fi
    while [[ -n "$remaining" ]]; do
        component="${remaining%%/*}"
        if [[ "$remaining" == */* ]]; then remaining="${remaining#*/}"; else remaining=""; fi
        case "$component" in
            ""|.) continue ;;
            ..) resolved="${resolved%/*}"; resolved="${resolved:-/}"; continue ;;
        esac
        candidate="${resolved%/}/$component"
        if [[ -d "$candidate" ]]; then
            resolved="$(cd "$candidate" && pwd -P)" || return 1
        elif [[ -e "$candidate" || -L "$candidate" ]]; then
            printf 'Preview path is not a directory: %s\n' "$candidate" >&2
            return 1
        else
            resolved="$candidate"
        fi
    done
    printf '%s\n' "$resolved"
}

DEST="$(canonical_destination "$DEST")"
USER_APPLICATIONS="$(canonical_destination "$HOME/Applications")"
reject_applications_destination() {
    case "$1/" in
    /Applications/*|"$USER_APPLICATIONS/"*)
        echo "Choose a preview output directory outside Applications." >&2
        return 1
        ;;
    esac
}

# Validate before mkdir, including missing children beneath an existing symlink.
reject_applications_destination "$DEST"
if [[ -e "$DEST/$NAME" || -e "$DEST/$ARCHIVE" ]]; then
    echo "Preview output already exists. Choose a new output directory." >&2
    exit 1
fi
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd -P)"
reject_applications_destination "$DEST"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/fileorbit-preview.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

# The production builder runs in a private directory. Its public artifact names
# never reach the preview destination or the repository's published output.
"$ROOT/scripts/build-app.sh" "$STAGE/build"
APP="$STAGE/$NAME"
ditto --norsrc --noextattr "$STAGE/build/FileOrbit.app" "$APP"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.fileorbit.preview" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName FileOrbit Preview" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName FileOrbit Preview" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :FileOrbitPreview bool true" "$PLIST"
# Do not register a second handler for the user's documents.
/usr/libexec/PlistBuddy -c "Delete :CFBundleDocumentTypes" "$PLIST"
plutil -lint "$PLIST"
codesign --force --sign - --entitlements "$ROOT/Resources/Entitlements.plist" "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$STAGE/$ARCHIVE"

# Copy only after the entire package has passed signature verification.
cp -X "$STAGE/$ARCHIVE" "$DEST/$ARCHIVE"
ditto --norsrc --noextattr "$APP" "$DEST/$NAME"
printf 'Preview app: %s\nPreview archive: %s\n' "$DEST/$NAME" "$DEST/$ARCHIVE"
