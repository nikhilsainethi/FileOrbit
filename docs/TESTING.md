# Verification record — October 24, 2026

## 0.3.0-preview.1 installed release validation — October 24, 2026

The user approved the optical preview for installation and publication. The production bundle was built separately, extracted-package verified, and installed at `/Applications/FileOrbit.app`. Its GUI executable matched the tested package: SHA-256 `77b8cfbae19e7370b53e215a91786066ee48f42f39f69437370b4a377fc6fb65`. The release ZIP SHA-256 is `32194f5ad4fe9feb58cf3c2a29b69f6f266bc626e3516ed3c546e9f07ba4a147`. Strict recursive code-signature validation passed after installation. The previous installation was retained for rollback.

- **125 source tests in 16 suites passed**, zero failures, 6.056 seconds after build, with real qpdf, resvg, cwebp and LibreOffice available.
- **29 production-package checks passed with zero skips**, 53.837 seconds. Their content and safety coverage is listed in the earlier optical-preview record below. The CI configuration now explicitly supplies the bundled cwebp path to source tests.
- **Physical Finder double-Command passed.** The user operated the actual Mac keyboard. Logs recorded recognized gestures reaching the Finder selection handler at 16:34:12.282, 16:34:20.383 and 16:34:25.817 local Pacific time. Native inspection confirmed that the wheel showed the selected PDF directly. After refreshing the ad-hoc signature's permission entry, the first attempt delivered no modifier events; restarting with permission already active restored delivery. No recognizer/backend change was made.
- **Physical Finder drag-to-convert passed.** The user dragged `Design study.png`, pressed Shift, and dropped on JPG. The resulting JPEG decoded at 4,096 × 4,096. SHA-256 verification showed the PNG source was unchanged.
- **Physical modifier switching and center drop passed.** The user confirmed Option → Modify, Control → Quick Actions, and a center drop. Native inspection then showed `Presentation study.pdf` (19 KB) retained in Glass Shelf.
- **Studio pointer-drag reordering passed.** The user dragged JPG onto PNG. Native accessibility inspection confirmed JPG moved from position 2 to position 1. Reset order restored PNG to position 1 and JPG to position 2. System appearance remained selected.

This validation combines automated checks, observed native UI state, and explicitly identified physical actions performed by the user. It does not imply all hardware/OS combinations were exercised. AirDrop recipient flow, Terminal routing, launch-at-login, multiple monitors/Spaces, full Xcode canvas macros, Intel hardware and older macOS remain outside this local run. The app remains ad-hoc signed and unnotarized; distribute it as a preview.

The following records describe earlier isolated and released builds; their verification limits are historical for those builds.

## 0.3 optical glass development preview — October 24, 2026

This record applies to the isolated `io.fileorbit.preview` candidate (version 0.3.0, build 3), not the public release. The production installation and public GitHub release were left unchanged. The same Apple Silicon/macOS 27.2 environment described below was used.

### Automated and packaged verification

- **125 tests in 16 suites passed**, zero failures, 6.278 seconds after build. Real qpdf, resvg, cwebp and LibreOffice were available. The run includes annular geometry, transformed hit testing, mode/preset state, late-arriving PDF metadata, transparent-gap rejection, stale drag-pasteboard handling, redaction-editor cancellation, mixed batches, and safe Undo checks.
- **29 extracted-package checks passed**, zero skips, 12.867 seconds against `FileOrbit-Glass-Preview-macOS-arm64.zip`. These exercise actual output content, not only process exit status: WebP pixels/alpha/dimensions; PDF first/all/tall exports; split-page order/content; Vision OCR; document Info/XMP/source-ID removal; raster redaction with hidden-object and OCR checks; Office conversion; compression; original integrity; naming collisions; signatures and license inventory.
- Compression fixture results: image **288,718 → 88,856 bytes**; deliberately uncompressed PDF **16,784,027 → 159,176 bytes**. These are test measurements, not promised savings.
- The bundled minimal cwebp 1.6.0/libpng 1.6.59 build uses only macOS system runtime libraries. Third-party notices and pinned source checksums are included.
- Independent specification and code-quality reviews found and prompted fixes for stale drag sessions, delayed metadata, gap drops, redaction cancellation, busy-export behavior, and Undo's immediate output snapshot. Regression tests cover those fixes.

### Native app observations

The real compiled preview was opened with native UI automation and visually inspected in Light and Dark appearances. System appearance was restored afterward. Actual Quick Look thumbnails, page counts, hover presets, mode switching, the Studio window and its appearance controls were observed. Accessible Studio reordering and Reset order worked.

A rectangular region was drawn on the sample PDF and exported to a separate flattened PDF. The result passed qpdf validation; the blacked-out region was visually inspected through the HUD's Space-bar Quick Look action. The HUD correctly reported that this 19 KB input produced a larger 182 KB rasterized output. A PDF-plus-JPEG shelf batch produced three PNG pages and one JPEG-to-PNG result; both rows reported Saved. A wheel-driven first-page PDF→WebP export produced a decodable 1,224 × 1,584 image (about 50 KB). SHA-256 checks confirmed that all four original sample files were unchanged after these operations.

Native Studio reopening initially exposed sizing and app-reopen interactions; the final candidate opens the Studio window without another wheel covering it. Screenshots in `docs/images/optical-wheel-*.jpg` are captures of the final running candidate.

### Explicit verification limits

- The preview deliberately disables global double-Command and Finder-drag monitoring. Their new-build physical-key delivery must be checked on the production candidate after preview approval; passing recognizer/state tests does not prove macOS event delivery. The original Command recognizer/backend was preserved.
- Studio's actual pointer-drag reorder gesture could not be completed reliably by the automation tool; its accessible reorder path and persistence tests passed. Cross-app drag/drop, AirDrop chooser/recipient flow, Terminal routing, login-at-startup and multi-monitor/Spaces behavior remain manual release checks.
- Full Xcode canvas macros, Intel hardware and older supported macOS versions were not run here. The normal Command Line Tools build compiled successfully.
- The app is ad-hoc signed, not Developer ID signed or notarized. This is a review preview, not a claim of broad production readiness.

The earlier release records below remain historical evidence for their named builds.

## Verified environment

- Apple Silicon Mac, macOS 27.2 (26B5112a).
- Apple Swift 6.2.3 and macOS SDK 26.2, standalone Command Line Tools.
- Application deployment target: macOS 15+; native Liquid Glass on 26+.
- LibreOffice 26.8.1.1 installed in Applications.
- qpdf 12.4.2 and resvg 0.49.0 bundled in the app. Official release checksums were verified before use.

## Automated source tests

**77 tests in 9 suites passed, zero failures.** The 0.2.0-preview.1 release run took 6.257 seconds after build. Real qpdf, resvg, and LibreOffice paths were supplied/detected; their integration checks were exercised.

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
- Rounded-petal hit testing and transparent gaps for one through seven actions, bottom compression placement, keyboard selection wrapping, zero-size geometry, and screen-edge/negative-origin panel placement.

Regression failures were observed before implementing fixes for stale selection, Caps Lock/Command event handling, PDF annotations/rotation, and encoded SVG resource references. The first GitHub run also exposed a test that included shared-queue timer delay in its cancellation deadline. The test now waits for a real child process, signals cancellation from an independent thread, and measures from that request while retaining the three-second bound and checking child cleanup. Converter behavior was unchanged.

Run:

```sh
./scripts/test.sh
```

The script locates real Swift Testing in standalone Command Line Tools. Full Xcode uses its normal framework setup. Install the optional converters before claiming full integration coverage.

## Packaged release checks

**19 packaged-app checks passed with no skips**, 7.876 seconds, against the 0.2.0-preview.1 arm64 release ZIP before installation.

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

### 0.2.0-preview.1

The installed release was extracted from the tested ZIP. Both executable hashes matched the archive, the app reported version 0.2.0, and strict recursive signature verification passed. System, Light and Dark appearance selections were exercised; System persisted after relaunch. LibreOffice, bundled qpdf and bundled resvg were available. The app permission entry was refreshed for the final ad-hoc signature, and the relaunched listener reported trusted access with both global and local event monitors registered.

The installed wheel completed arrow-key/Return PNG→HEIC conversion (199,308 bytes at 4,096 × 4,096) and Small-preset PNG compression (743,748 → 528,209 bytes at 1,600 × 1,600). The source SHA-256 remained unchanged. A pre-existing compressed copy was preserved and the new copy received a unique name. Escape returned from compression to the action wheel.

**Live shortcut on the exact release build:** the physical left-Command sequence at 15:24:46.035 local time was recognized with Finder active and reached the selection handler. The wheel showed the selected `Photo sample.jpg` directly, without a file picker. Return then produced `Photo sample-converted.pdf`, which passed qpdf validation. The installed GUI executable still matched the tested archive's SHA-256 (`0e6e4ff9bdb4e5e89a63743d3bdca32cf5b1b900a932fb22aac035b1f1fc1632`).

Initial post-update attempts produced no modifier events in the diagnostic log despite authorized access. A temporary read-only Quartz listener was used to compare delivery; both it and the existing AppKit listener subsequently received the same physical gesture. The temporary instrumentation was removed, the exact tested release was restored and reauthorized, and the release check above succeeded. The cause of the earlier missing events was not established; no speculative shortcut-backend change was included. Diagnostic logging was disabled after validation.

### Earlier 0.1.0 preview verification

The observations below describe the earlier public build and are retained as historical evidence.


The installed app was opened and inspected using native UI automation. Observed successful PNG→JPEG conversion, arrow-key/Return HEIC conversion, result sizes, return navigation, native file picking, compression preset selection, successful PNG compression (744 KB to 528 KB), the no-larger-output alert, and Settings showing all three available engines. The glass wheel, compression controls, result screen and Settings were visually inspected. A native-background compositing issue that hid unchanged header/footer controls after processing was reproduced and resolved by using SwiftUI native material; the final result screen was re-inspected. Reopening the normal background app displays its command panel.

**Live Finder shortcut verified:** Physical left-Command press/release sequences produced three recognized double-taps with Finder active at 11:50:25.549, 11:50:30.612 and 11:50:38.984 local time. Each reached the Finder-gesture handler. macOS TCC recorded Finder Automation access as allowed at 11:50:27.947. Visual inspection confirmed that the glass wheel showed the selected DOCX file with PDF, TXT and Compress actions directly, without another file picker. TIFF and PDF outputs were also observed in the test folder (1,907,756 and 421,838 bytes respectively). The TIFF decoded successfully at 4,096 × 4,096 pixels using `sips`; the PDF passed `qpdf --check` with no syntax or stream errors.

During setup, an enabled permission entry referred to an earlier ad-hoc build; TCC logs confirmed its code-signature requirement did not match the installed app. The current app was re-added to the macOS permission list after the user completed device authentication. Subsequent attempts initially appeared to do nothing. Opt-in diagnostic logging was then added, and the physical gesture succeeded as described above. The recognizer was not changed; the exact cause of the earlier attempts without logs was not established. Diagnostics were turned off after verification. On this macOS 27 build, the Accessibility pane is named Device Control and Data Access.

Login-at-startup, multi-monitor/Spaces behavior, older macOS versions and Intel hardware were not exercised here. Unit/event-adapter tests validate recognition logic separately from the live OS check.

## Packaging notes

The app is **ad-hoc signed**, not Developer ID signed or notarized. Both the installed `/Applications/FileOrbit.app` and the app extracted from the final ZIP passed strict signature validation.

This Mac's cloud-backed Documents folder attaches Finder metadata to loose `.app` bundles. Signing and ZIP creation therefore occur in clean system temporary storage before delivery. The distributable is the ZIP; use the installed Applications copy for running. The loose app generated inside a synced output folder is not the release artifact.

The public download is an Apple Silicon preview. The build includes third-party dependency notices and strips local debug paths before signing. The GitHub Actions workflow separately runs source tests and verifies a packaged app on macOS 26 with Xcode 26.2. A stable release still needs broader supported-platform testing and Developer ID signing/notarization.
