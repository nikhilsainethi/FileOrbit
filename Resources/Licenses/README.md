# Bundled software notices

These files preserve original upstream license and copyright texts for the helpers distributed with the FileOrbit Apple Silicon preview. The app bundle contains this directory at `Contents/Resources/Licenses`, alongside `THIRD_PARTY_NOTICES.md`.

- `qpdf/`: qpdf 12.4.2 Apache license and full upstream NOTICE, including its embedded SHA-2 notice and public-domain Rijndael attribution.
- `openssl/`: OpenSSL 3.6.4 Apache license and upstream author attribution. Statically linked into the official qpdf macOS arm64 helper.
- `libjpeg-turbo/`: libjpeg-turbo 3.2.0 license roll-up and unmodified IJG README. Statically linked into the official qpdf macOS arm64 helper.
- `resvg/`: resvg/usvg 0.49.0 and their default-feature normal/build dependencies for aarch64-apple-darwin. Includes build-only packages conservatively; excludes test-only font fixtures.
- `rust/`: Rust runtime license texts and the upstream standard-library copyright report for Rust 1.99.1. The resvg binary contains the compiler revision `58cf8f9c35b355199727627d07ae34a4e2846d67`, whose source version is 1.99.1. The standard-library report includes notices for multiple supported platforms, so it is broader than the code linked on this Mac.
- `unicode/`: Unicode License V3 and the original Unicode emoji-data attribution present in harfrust. The unicode-ident package also retains its own upstream Unicode license in `resvg/`.

[RESVG-DEPENDENCIES.md](RESVG-DEPENDENCIES.md) links every collected crate license. `resvg-dependencies.json` records versions, publisher archive URLs, lockfile checksums and license-file hashes. `resvg-Cargo.lock` is copied unchanged from the upstream release tag.

## Provenance

- qpdf source tag: https://github.com/qpdf/qpdf/tree/v12.4.2 ; resolved commit `4eba95899886e851cc41d76886483b347612f2a8`.
- qpdf macOS packaging recipe: https://github.com/qpdf/qpdf/blob/v12.4.2/build-scripts/build-mac-bin . It statically links OpenSSL and JPEG. The distributed arm64 library contains `libjpeg-turbo version 3.2.0 (build 20260630)` and OpenSSL `3.6.4` / Homebrew 3.6.4 paths.
- OpenSSL source tag: https://github.com/openssl/openssl/tree/openssl-3.6.4 ; resolved commit `d3c1b1169b3569ff3069e5b399f47b2b28e03d79`.
- libjpeg-turbo source tag: https://github.com/libjpeg-turbo/libjpeg-turbo/tree/3.2.0 ; resolved commit `c85e6b905bf237038faa936dab160ebfc5da0344`.
- resvg source tag: https://github.com/linebender/resvg/tree/v0.49.0 ; resolved commit `66ee0dc7d787d7e0b0ab3085b7849f78838cf2ba`.
- resvg release recipe: https://github.com/linebender/resvg/blob/v0.49.0/.github/workflows/tagged-release.yml . Uses `cargo build --release` with the default features.
- Crate license texts come from publisher-supplied packages obtained by `cargo metadata --locked --format-version 1 --filter-platform aarch64-apple-darwin`; only normal/build dependency edges reachable from the resvg package were selected. Cargo checks the packages against the release lockfile.
- Rust source: https://github.com/rust-lang/rust/tree/58cf8f9c35b355199727627d07ae34a4e2846d67 . Standard-library copyright report extracted verbatim from https://static.rust-lang.org/dist/rustc-1.99.1-aarch64-apple-darwin.tar.xz ; archive SHA-256 `23948a0a9c162fd2952defb3fb0462c44e8fcfd1a4ab8a274a1e1bdb2cf810a3`, matched against the upstream `.sha256` file.
- Unicode license: https://www.unicode.org/license.txt ; retrieved October 24, 2026. Original emoji-data attribution is copied from harfrust 0.12.0 `src/hb/unicode_emoji_table.rs`.

The helper asset URLs and SHA-256 checksums are pinned in `scripts/fetch-helpers.sh`. This inventory is specific to those Apple Silicon assets and must be refreshed when helper versions, features, or architecture change. It records inspected upstream notices and binary linkage; it is not a legal certification or a claim of bit-for-bit reproduction of upstream binaries.
