#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="${FILEORBIT_VENDOR_DIR:-$ROOT/.build/vendor}"
case "$(uname -m)" in
  arm64)
    QPDF_ARCH=arm64; RESVG_ARCH=aarch64
    QPDF_SHA=62e46987a30ea167cbc530ccb22690aec3d8c812ed09979a941bcee92e504b79
    RESVG_SHA=847acb5210c7c6244b5e8f07dd62fa1ce596108cce8193628ebfd5750504b259 ;;
  x86_64)
    QPDF_ARCH=x86_64; RESVG_ARCH=x86_64
    QPDF_SHA=dd3b01f4414d198529bb0f13bba59c2f016a328bb3506695087a96fb80fc1481
    RESVG_SHA=7c92cba55348f0254707c8d2c61e71651296981f8ccfadf8477782e91db5e171 ;;
  *) echo 'Unsupported architecture.' >&2; exit 1 ;;
esac
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
curl --fail --location "https://github.com/qpdf/qpdf/releases/download/v12.4.2/qpdf-12.4.2-bin-macos-$QPDF_ARCH.zip" -o "$STAGE/qpdf.zip"
curl --fail --location "https://github.com/linebender/resvg/releases/download/v0.49.0/resvg-macos-$RESVG_ARCH.zip" -o "$STAGE/resvg.zip"
printf '%s  %s\n' "$QPDF_SHA" "$STAGE/qpdf.zip" "$RESVG_SHA" "$STAGE/resvg.zip" | shasum -a 256 --check
mkdir -p "$VENDOR/qpdf" "$VENDOR/resvg"
unzip -oq "$STAGE/qpdf.zip" -d "$VENDOR/qpdf"
unzip -oq "$STAGE/resvg.zip" -d "$VENDOR/resvg"
"$VENDOR/qpdf/bin/qpdf" --version
"$VENDOR/resvg/resvg" --version
printf 'Verified helpers saved in %s\n' "$VENDOR"
