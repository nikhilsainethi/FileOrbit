#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
developer_dir="$(xcode-select -p)"
framework_dir="$developer_dir/Library/Developer/Frameworks"

# The standalone Apple Command Line Tools ship Swift Testing outside the SDK.
# Their Foundation cross-import overlay does not include Swift module metadata.
# Full Xcode does not need these discovery/overlay flags.
if [[ "$developer_dir" == */CommandLineTools && -d "$framework_dir/Testing.framework" ]]; then
    exec swift test --disable-xctest \
        -Xswiftc -F -Xswiftc "$framework_dir" \
        -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
        -Xlinker -rpath -Xlinker "$framework_dir" "$@"
else
    exec swift test --disable-xctest "$@"
fi
