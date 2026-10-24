# Third-party notices

FileOrbit's application source is licensed under [MIT](LICENSE). Third-party components retain their own licenses. Their original license texts and copyright notices are included in [Resources/Licenses](Resources/Licenses/README.md) and in the downloadable app at `Contents/Resources/Licenses`.

**This software is based in part on the work of the Independent JPEG Group.**

## Bundled in the Apple Silicon preview

| Component | Version | License and notices | Upstream source |
| --- | --- | --- | --- |
| qpdf, libqpdf and qpdf utility executables | 12.4.2 | [Apache-2.0](Resources/Licenses/qpdf/LICENSE.txt), [NOTICE](Resources/Licenses/qpdf/NOTICE.md) | [qpdf](https://github.com/qpdf/qpdf/tree/v12.4.2) |
| OpenSSL, statically linked into qpdf | 3.6.4 | [Apache-2.0](Resources/Licenses/openssl/LICENSE.txt), [authors](Resources/Licenses/openssl/AUTHORS.md) | [OpenSSL](https://github.com/openssl/openssl/tree/openssl-3.6.4) |
| libjpeg-turbo, statically linked into qpdf | 3.2.0 | [License roll-up](Resources/Licenses/libjpeg-turbo/LICENSE.md), [IJG README](Resources/Licenses/libjpeg-turbo/README.ijg) | [libjpeg-turbo](https://github.com/libjpeg-turbo/libjpeg-turbo/tree/3.2.0) |
| resvg / usvg | 0.49.0 | MIT or Apache-2.0; complete texts in [resvg](Resources/Licenses/resvg/resvg-0.49.0) and [usvg](Resources/Licenses/resvg/usvg-0.49.0) | [resvg](https://github.com/linebender/resvg/tree/v0.49.0) |
| resvg Rust dependencies | Pinned by upstream Cargo.lock | MIT, Apache-2.0, BSD, Zlib, Unicode and other permissive alternatives as declared per package; [64-package inventory and exact texts](Resources/Licenses/RESVG-DEPENDENCIES.md) | Publisher archive/source links in the inventory |
| Rust standard-library runtime linked into resvg | 1.99.1 | [MIT](Resources/Licenses/rust/LICENSE-MIT) or [Apache-2.0](Resources/Licenses/rust/LICENSE-APACHE), with [standard-library component notices](Resources/Licenses/rust/COPYRIGHT-library.html) | [Rust compiler revision](https://github.com/rust-lang/rust/tree/58cf8f9c35b355199727627d07ae34a4e2846d67) |
| Unicode data used by text dependencies | As attributed upstream | [Unicode License V3](Resources/Licenses/unicode/LICENSE.txt), [emoji-data attribution](Resources/Licenses/unicode/harfrust-emoji-data-attribution.txt), and crate-specific notices | [Unicode](https://www.unicode.org/license.txt) |

The qpdf upstream NOTICE also preserves attribution for public-domain Rijndael code and the MIT-licensed sphlib SHA-2 code. It mentions qtest, an upstream testing component; FileOrbit does not bundle the qtest test framework. resvg test fonts are not bundled. Build-only Rust dependencies are included in the license inventory conservatively.

The official qpdf macOS build statically links OpenSSL and JPEG. Versions above were identified from the arm64 binary and checked against the upstream packaging recipe. resvg's normal/build dependency inventory comes from the v0.49.0 release lockfile and default-feature graph for `aarch64-apple-darwin`. [License provenance and checksums](Resources/Licenses/README.md) explain how the notice set was collected.

## Supplied separately

- **LibreOffice** is installed independently by the user and is not redistributed in FileOrbit. See [The Document Foundation's license information](https://www.libreoffice.org/about-us/licenses/). Office conversion requires this optional installation.
- **Apple frameworks and system libraries**, including AppKit, SwiftUI, ImageIO, CoreGraphics, PDFKit, Foundation, libc++, zlib and libiconv, are supplied by macOS. FileOrbit does not copy these libraries into its app.

`fetch-helpers.sh` pins upstream download URLs and SHA-256 hashes. Compiled helpers are excluded from the Git source tree and included only in packaged app downloads. The packaging script must retain this notice file and the complete license directory. Refresh this inventory before changing helper versions, build features or architecture; the bundled-dependency inspection described here covers the published arm64 preview.
