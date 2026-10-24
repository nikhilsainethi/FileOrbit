# Verification record — October 24, 2026

## Verified environment

- Apple Silicon Mac, macOS 27.2 (26B5112a).
- Apple Swift 6.2.3 and macOS SDK 26.2, standalone Command Line Tools.
- Application deployment target: macOS 15+; native Liquid Glass on 26+.
- LibreOffice 26.8.1.1 installed in Applications.
- qpdf 12.4.2 and resvg 0.49.0 bundled in the app. Official release checksums were verified before use.

## Automated source tests

**69 tests in 7 suites passed, zero failures.** Latest local full run: 4.625 seconds after build. Real qpdf, resvg, and LibreOffice paths were supplied/detected; their integration checks were exercised.

Coverage includes:

- Two completed Command taps, timing boundaries, long holds, chords, mouse interference, invalid timestamps, overlapping Command keys, Caps Lock, reset and no repeated triple-tap trigger.
- Capability filtering, installed/missing converter states, runtime image encoders, animated/multipage image rejection, explicit Settings and bundled-helper discovery.
- Clearing stale input after a failed new selection.
- JPEG/PNG/HEIC/TIFF output decoding, transparency, white JPEG background, EXIF orientation, source hashes, image-to-PDF and compression output size/dimensions.
- PDF text/page export, visible annotations at four rotations, no-text PDFs, encrypted PDFs and signature-bearing widgets.
- Static SVG rendering, linked-resource rejection including encoded stylesheet references, and use of validated staged content.
- Filename collisions, atomic multi-page output folders, corrupt/missing inputs, cancellation and refusal to publish larger compression results.
- Literal Unicode/space-containing subprocess arguments, bounded output, deadlines, cancellation and child-process cleanup.
- Real TXT→PDF/DOCX→TXT and two-slide PPTX→PDF/images; DOCX media compression preserves XML and relationships.
- Unsafe ZIP paths, symlinks, signed DOCX and linked Office-resource rejection.

Regression failures were observed before implementing fixes for stale selection, Caps Lock/Command event handling, PDF annotations/rotation, and encoded SVG resource references. The first GitHub run also exposed a test that included shared-queue timer delay in its cancellation deadline. The test now waits for a real child process, signals cancellation from an independent thread, and measures from that request while retaining the three-second bound and checking child cleanup. Converter behavior was unchanged.

Run:

```sh
./scripts/test.sh
```

The script locates real Swift Testing in standalone Command Line Tools. Full Xcode uses its normal framework setup. Install the optional converters before claiming full integration coverage.

## Packaged release checks

**19 packaged-app checks passed with no skips**, 8.958 seconds, against the public preview arm64 ZIP.

The verifier extracts the ZIP into an independent system temporary directory and checks:

- Strict recursive code-signature validation.
- Removal of local build paths from both app executables.
- Included application/dependency notices, with all 126 resvg dependency license files verified against their recorded hashes.
- Separate GUI and CLI executables, and CLI JSON output under a timeout.
- Discovery and execution of bundled qpdf/resvg rather than development overrides.
- Actual SVG→PNG and PNG→JPEG/HEIC/TIFF/PDF operations.
- Original-file hashes, accurate byte counts and collision protection.
- Image compression: **288,718 → 88,856 bytes** for the JPEG fixture.
- PDF compression: **16,784,027 → 159,176 bytes** for the deliberately uncompressed PDF fixture, preserving page count and passing qpdf validation. This is a test fixture, not a typical savings claim.
- Actual LibreOffice TXT→PDF/DOCX→TXT with sentinel text preserved.
- Removal of temporary processing folders.

Run:

```sh
python3 scripts/verify-package.py /path/to/FileOrbit-macOS-arm64.zip
```

Exit 0 means all checks passed. Exit 3 explicitly reports partial coverage from unavailable engines/encoders. Exit 1 means failure.

## Native UI observations

The installed app was opened and inspected using native UI automation. Observed successful PNG→JPEG conversion, arrow-key/Return HEIC conversion, result sizes, return navigation, native file picking, compression preset selection, successful PNG compression (744 KB to 528 KB), the no-larger-output alert, and Settings showing all three available engines. The glass wheel, compression controls, result screen and Settings were visually inspected. A native-background compositing issue that hid unchanged header/footer controls after processing was reproduced and resolved by using SwiftUI native material; the final result screen was re-inspected. Reopening the normal background app displays its command panel.

**Live Finder shortcut verified:** Physical left-Command press/release sequences produced three recognized double-taps with Finder active at 11:50:25.549, 11:50:30.612 and 11:50:38.984 local time. Each reached the Finder-gesture handler. macOS TCC recorded Finder Automation access as allowed at 11:50:27.947. Visual inspection confirmed that the glass wheel showed the selected DOCX file with PDF, TXT and Compress actions directly, without another file picker. TIFF and PDF outputs were also observed in the test folder (1,907,756 and 421,838 bytes respectively). The TIFF decoded successfully at 4,096 × 4,096 pixels using `sips`; the PDF passed `qpdf --check` with no syntax or stream errors.

During setup, an enabled permission entry referred to an earlier ad-hoc build; TCC logs confirmed its code-signature requirement did not match the installed app. The current app was re-added to the macOS permission list after the user completed device authentication. Subsequent attempts initially appeared to do nothing. Opt-in diagnostic logging was then added, and the physical gesture succeeded as described above. The recognizer was not changed; the exact cause of the earlier attempts without logs was not established. Diagnostics were turned off after verification. On this macOS 27 build, the Accessibility pane is named Device Control and Data Access.

Login-at-startup, multi-monitor/Spaces behavior, older macOS versions and Intel hardware were not exercised here. Unit/event-adapter tests validate recognition logic separately from the live OS check.

## Packaging notes

The app is **ad-hoc signed**, not Developer ID signed or notarized. Both the installed `/Applications/FileOrbit.app` and the app extracted from the final ZIP passed strict signature validation.

This Mac's cloud-backed Documents folder attaches Finder metadata to loose `.app` bundles. Signing and ZIP creation therefore occur in clean system temporary storage before delivery. The distributable is the ZIP; use the installed Applications copy for running. The loose app generated inside a synced output folder is not the release artifact.

The public download is an Apple Silicon preview. The build includes third-party dependency notices and strips local debug paths before signing. The GitHub Actions workflow separately runs source tests and verifies a packaged app on macOS 26 with Xcode 26.2. A stable release still needs broader supported-platform testing and Developer ID signing/notarization.
