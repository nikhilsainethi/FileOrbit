#!/bin/bash
set -euo pipefail
if ! command -v brew >/dev/null 2>&1; then
  echo 'Install LibreOffice from https://www.libreoffice.org/download/download-libreoffice/'
  echo 'The packaged FileOrbit app includes qpdf, resvg and cwebp. Source builds can run scripts/fetch-helpers.sh.'
  exit 1
fi
brew install qpdf resvg webp
brew install --cask libreoffice
