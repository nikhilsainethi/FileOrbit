FileOrbit cwebp helper: source and license provenance

The distributable helper is built by scripts/build-webp-helper.sh from these
unmodified upstream release archives:

libwebp 1.6.0 (including its SharpYUV encoder support)
https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz
SHA256 e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
Notices copied verbatim into libwebp/COPYING, libwebp/PATENTS, and libwebp/AUTHORS.

libpng 1.6.59
https://downloads.sourceforge.net/project/libpng/libpng16/1.6.59/libpng-1.6.59.tar.gz
SHA256 86a3e4b501f7f50e392c4e456ea158893e9a595b1c63eb88c7bb9f6cf8772dad
License copied verbatim into libpng/LICENSE.

Both libraries are linked statically. The helper enables the optional PNG reader
and disables the JPEG, TIFF, GIF, and SDL dependencies. Upstream's built-in WebP,
PNM/PAM, and raw-YUV readers remain available; they require no extra libraries.
FileOrbit supplies normalized PNG input to this helper.

The executable links dynamically only to Apple's system libraries, including
system zlib. It does not redistribute zlib, JPEG, TIFF, Zstandard, or LZMA code.
The build verifies source checksums and runtime library paths before installing
the helper. Its output and upstream notices are saved under cwebp/ in
FILEORBIT_VENDOR_DIR (default: the repository's .build/vendor directory).
