# FileOrbit

**Select a file. Tap ⌘ twice. Convert it.**

FileOrbit is a native macOS menu-bar app that brings a glass conversion wheel to the file you selected in Finder. Convert images, PDFs and documents, or make a smaller copy—all on your Mac, without uploading the file or opening another file picker.

<p>
  <img src="docs/images/glass-wheel-light.jpg" alt="Frameless FileOrbit conversion wheel in Light mode" width="340">
  <img src="docs/images/glass-wheel-dark.jpg" alt="Frameless FileOrbit conversion wheel in graphite and smoky lavender Dark mode" width="340">
</p>

[Download the Apple Silicon preview](https://github.com/nikhilsainethi/FileOrbit/releases/download/v0.2.0-preview.1/FileOrbit-macOS-arm64.zip) · [Installation guide](docs/INSTALL.md) · [Release notes](https://github.com/nikhilsainethi/FileOrbit/releases/tag/v0.2.0-preview.1)

> **Preview release:** the download is ad hoc signed, but it is **not Developer ID signed or notarized by Apple**. macOS may block its first launch. Read the [first-launch instructions](docs/INSTALL.md#first-launch-and-macos-security) before installing. The binary is for Apple Silicon; macOS 15+ is the deployment target, and macOS 27.2 on Apple Silicon is the locally tested configuration. Older macOS versions and Intel builds still need verification.

## Get started

1. Download and unzip `FileOrbit-macOS-arm64.zip`, then move **FileOrbit.app** to **Applications**.
2. Open FileOrbit. In its Settings, enable the Finder shortcut in **System Settings → Privacy & Security → Accessibility**. On the tested macOS 27 build, this pane is called **Device Control and Data Access**.
3. In Finder, select one file. Press and release the same **⌘ key twice quickly**. Allow FileOrbit to control Finder when macOS asks; this lets it read your selection.
4. Choose a format or **Compress** from the wheel. The result is saved beside the original, with a new name.

For DOCX, PPTX and TXT **conversion**, install [LibreOffice](https://www.libreoffice.org/download/) separately. Images, PDF tools, SVG rendering and DOCX image compression work without LibreOffice. The preview includes qpdf and resvg; there is no need to install them separately.

See the [installation guide](docs/INSTALL.md) for permissions, troubleshooting, updates and uninstalling.

## What it does

- **Works where your files are.** Double-tap Command in Finder to open actions for the current selection.
- **Runs locally.** No conversion servers, accounts, subscriptions or telemetry.
- **Keeps originals intact.** Existing files are never overwritten; compression saves a copy only when it is smaller.
- **Fits macOS.** Frameless floating petals, a compact file hub, keyboard navigation and Liquid Glass on macOS 26+, with a native material fallback on earlier versions. Choose System, Light or Dark appearance in Settings.
- **Shows available actions.** Formats depend on the selected file, macOS encoders and installed local converters.

| Input | Convert to | Compress |
| --- | --- | --- |
| Single-frame images readable by macOS | PNG, JPEG, HEIC, TIFF, PDF¹ | JPEG, PNG, HEIC and TIFF |
| PDF | PNG/JPEG per page; existing text layer to TXT | Structure optimization; optional eligible-image recompression |
| DOCX | PDF, TXT² | Embedded JPEG/PNG optimization |
| PPTX | PDF, PNG/JPEG per slide² | — |
| TXT | PDF, DOCX² | — |
| Static, self-contained SVG | PNG, JPEG | — |

¹ Image outputs depend on encoders available on your Mac. Same-format conversions are omitted. Animated and multipage images are not supported.

² Requires local LibreOffice. Complex Office layouts and fonts can render differently from Microsoft Office.

## Using the wheel

Click an action, or use the arrow keys and press **Return**. **Escape** or a click outside closes the idle wheel. Compression stays at the bottom of the wheel and opens three size/quality presets; the app explains when a file is already small enough that it cannot produce a smaller copy.

New files use `-converted` or `-compressed` names beside the source. Name collisions receive a unique name. Multipage image exports are placed in a new folder. The result screen shows the output size and a **Show in Finder** button.

Settings and **Choose File…** are available from the menu-bar icon. FileOrbit also supports drag-and-drop, **Choose a file**, and Finder’s **Open With** menu. These are optional entry points and work without shortcut permissions. Launch at login is optional and off by default.

## Current limits

This preview focuses on conversion and compression. It does not include editing, editable PDF-to-Office conversion, OCR, vector tracing, animated/multipage image conversion, batch processing or password entry. Scanned PDFs need an existing text layer for TXT export.

Compression can resize or recompress images, including images inside DOCX; it is not always lossless. PDF’s Gentle preset optimizes structure without lossy image conversion. Metadata can change, and transparent images get a white background when converted to JPEG.

Encrypted/locked PDFs and PDFs with signature fields cannot be compressed. Signed DOCX compression, Office macros/embedded objects/linked resources, and SVG scripts/animation/external resources are rejected. Ordinary Office hyperlinks remain allowed.

Inputs and exports have resource limits to keep work bounded: general input 1 GB, Office input 256 MB, TXT 32 MB, and expanded Office packages 512 MB. PDF image export is capped at 144 DPI, 8,192 pixels per side and 32 megapixels per page; SVG output is capped at 2,048 pixels per side. Errors explain unsupported cases.

## Build from source

You need a Mac, Git, and Xcode or Command Line Tools with **Swift 6.2+ and the macOS 26 SDK or later**.

```sh
git clone https://github.com/nikhilsainethi/FileOrbit.git
cd FileOrbit

# If you use Homebrew: install qpdf, resvg and LibreOffice for integration tests.
./scripts/install-dependencies.sh
./scripts/test.sh

# Fetch pinned, checksum-verified helpers for the app bundle.
./scripts/fetch-helpers.sh
./scripts/build-app.sh
```

The build produces `dist/FileOrbit.app` and an architecture-specific ZIP. Extract the ZIP and move the app to Applications before granting permissions. This also avoids Finder metadata that synced folders can attach to loose app bundles. Building signs the app ad hoc; it does not notarize it.

Without Homebrew, install LibreOffice from its official site, run `fetch-helpers.sh`, and supply the fetched engines when testing:

```sh
FILEORBIT_QPDF="$PWD/.build/vendor/qpdf/bin/qpdf" \
FILEORBIT_RESVG="$PWD/.build/vendor/resvg/resvg" \
./scripts/test.sh
```

The helper download script has arm64 and x86_64 targets, but this release only provides a tested arm64 binary. See the [verification record](docs/TESTING.md) for exact local coverage and remaining platform checks.

### Command-line use

The CLI shares the app’s conversion engine:

```sh
swift run fileorbit-cli --engines
swift run fileorbit-cli --capabilities /absolute/path/photo.png
swift run fileorbit-cli /absolute/path/photo.png --to jpg
swift run fileorbit-cli /absolute/path/report.pdf --compress balanced
swift run fileorbit-cli /absolute/path/slides.pptx --to png --output-dir /existing/output/folder
```

It returns JSON and a nonzero exit status on errors. Use `FILEORBIT_SOFFICE`, `FILEORBIT_QPDF` and `FILEORBIT_RESVG` to override converter paths. GUI Settings can also locate installed engines.

## Development and contributing

The project uses Swift Package Manager:

- `FileOrbitCore` contains capability discovery, converters, process supervision, output publication and the gesture recognizer.
- `FileOrbit` contains the AppKit menu bar/panel, SwiftUI wheel, Settings and Finder integration.
- `FileOrbitCLI` exposes the conversion engine from Terminal.
- `Tests` covers file integrity, formats, cancellation, subprocesses, gesture recognition and state regressions.

Bug reports and pull requests are welcome. When [reporting an issue](https://github.com/nikhilsainethi/FileOrbit/issues), include your macOS version, chip, source format, action and exact error. Use a small, non-sensitive sample if one is needed. Read [Contributing](CONTRIBUTING.md) before submitting changes and [Security](SECURITY.md) for vulnerability reporting. The [installation guide](docs/INSTALL.md#shortcut-diagnostics) explains opt-in shortcut diagnostics.

## License

FileOrbit is available under the [MIT License](LICENSE). Bundled third-party components retain their own licenses; see [Third-party notices](THIRD_PARTY_NOTICES.md).
