#!/bin/bash
set -euo pipefail

# Build only the distributable cwebp helper. libwebp and libpng are linked
# statically; zlib and libc remain Apple's system libraries. No package manager,
# CMake, or autotools installation is required: release tarballs ship configure.
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
vendor_dir="${FILEORBIT_VENDOR_DIR:-$repo_root/.build/vendor}"
mkdir -p "$vendor_dir"
vendor_dir="$(cd "$vendor_dir" && pwd)"
cache_dir="$vendor_dir/.source-cache"
output_dir="$vendor_dir/cwebp"
mkdir -p "$cache_dir" "$output_dir"

if [[ "$(uname -s)" != Darwin ]]; then
    echo 'This helper build targets macOS and requires Apple Command Line Tools.' >&2
    exit 1
fi
for required in xcrun make curl shasum tar otool; do
    command -v "$required" >/dev/null || { echo "Missing required build tool: $required" >&2; exit 1; }
done

webp_version=1.6.0
webp_url="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$webp_version.tar.gz"
webp_sha=e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
png_version=1.6.59
png_url="https://downloads.sourceforge.net/project/libpng/libpng16/$png_version/libpng-$png_version.tar.gz"
png_sha=86a3e4b501f7f50e392c4e456ea158893e9a595b1c63eb88c7bb9f6cf8772dad

download_verified() {
    local url="$1" destination="$2" expected="$3" actual
    if [[ ! -f "$destination" ]]; then
        curl --fail --location --retry 3 --output "$destination.partial" "$url"
        mv "$destination.partial" "$destination"
    fi
    actual="$(shasum -a 256 "$destination" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        echo "SHA256 mismatch for $destination; remove the cached archive and retry." >&2
        exit 1
    fi
}

download_verified "$webp_url" "$cache_dir/libwebp-$webp_version.tar.gz" "$webp_sha"
download_verified "$png_url" "$cache_dir/libpng-$png_version.tar.gz" "$png_sha"

build_dir="$(mktemp -d "$vendor_dir/.cwebp-build.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
# Autoconf/libtool compiler flags cannot represent a prefix containing whitespace.
# Preserve arbitrary destination paths by putting only the temporary build there.
if [[ "$build_dir" =~ [[:space:]] ]]; then
    rmdir "$build_dir"
    build_dir="$(mktemp -d /tmp/fileorbit-cwebp.XXXXXX)"
fi
prefix="$build_dir/prefix"
tar -xzf "$cache_dir/libwebp-$webp_version.tar.gz" -C "$build_dir"
tar -xzf "$cache_dir/libpng-$png_version.tar.gz" -C "$build_dir"

export CC="$(xcrun --find clang)"
export CXX="$(xcrun --find clang++)"
export MACOSX_DEPLOYMENT_TARGET=15.0
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
export CFLAGS="-O3 -fvisibility=hidden -isysroot $sdk_path -mmacosx-version-min=15.0"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="-isysroot $sdk_path"
export LDFLAGS="-isysroot $sdk_path -mmacosx-version-min=15.0 -Wl,-dead_strip"
export LIBS="-lz"
# Avoid accidentally discovering optional libraries from an installed Homebrew.
export PKG_CONFIG=/usr/bin/false
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH PKG_CONFIG_PATH
jobs="${FILEORBIT_BUILD_JOBS:-$(sysctl -n hw.logicalcpu)}"

(
    cd "$build_dir/libpng-$png_version"
    ./configure --prefix="$prefix" --disable-shared --enable-static --disable-tools --disable-tests
    make -j "$jobs"
    make install
)
(
    cd "$build_dir/libwebp-$webp_version"
    LIBPNG_CONFIG="$prefix/bin/libpng16-config" ./configure \
        --prefix="$prefix" --disable-shared --enable-static \
        --disable-jpeg --disable-tiff --disable-gif --disable-sdl \
        --disable-libwebpmux \
        --with-pngincludedir="$prefix/include" --with-pnglibdir="$prefix/lib"
    # Fail closed: a successful configure without PNG would silently break input.
    grep -q '^#define WEBP_HAVE_PNG 1' src/webp/config.h
    if grep -Eq '^#define WEBP_HAVE_(JPEG|TIFF|GIF|SDL) 1' src/webp/config.h; then
        echo 'An unwanted optional image library was detected.' >&2
        exit 1
    fi
    make -j "$jobs"
)

candidate="$build_dir/libwebp-$webp_version/examples/cwebp"
[[ -x "$candidate" ]] || { echo 'The cwebp executable was not built.' >&2; exit 1; }
actual_version="$("$candidate" -version)"
[[ "${actual_version%%$'\n'*}" == "$webp_version" ]] || { echo "Unexpected cwebp version: $actual_version" >&2; exit 1; }
# Exercise the compiled PNG reader and encoder with upstream's own PNG fixture.
"$candidate" -quiet -lossless "$build_dir/libpng-$png_version/pngtest.png" -o "$build_dir/verify.webp"
"$build_dir/libwebp-$webp_version/examples/dwebp" -quiet "$build_dir/verify.webp" -o "$build_dir/verify.png"
[[ -s "$build_dir/verify.png" ]] || { echo 'PNG/WebP encode-decode verification failed.' >&2; exit 1; }
dependencies="$(otool -L "$candidate")"
# Allow only platform libraries, never a locally installed codec dylib.
while IFS= read -r dependency; do
    case "$dependency" in
        /usr/lib/*|/System/Library/*) ;;
        *) echo "Unexpected runtime dependency: $dependency" >&2; exit 1 ;;
    esac
done < <(printf '%s\n' "$dependencies" | tail -n +2 | awk '{print $1}')

mkdir -p "$output_dir/licenses/libwebp" "$output_dir/licenses/libpng"
cp "$build_dir/libwebp-$webp_version/"{COPYING,PATENTS,AUTHORS} "$output_dir/licenses/libwebp/"
cp "$build_dir/libpng-$png_version/LICENSE" "$output_dir/licenses/libpng/LICENSE"
cp "$candidate" "$output_dir/cwebp.new"
chmod 755 "$output_dir/cwebp.new"
strip -S "$output_dir/cwebp.new"
mv "$output_dir/cwebp.new" "$output_dir/cwebp"
printf 'Built cwebp %s for %s at %s\n' "$webp_version" "$(uname -m)" "$output_dir/cwebp"
otool -L "$output_dir/cwebp"
