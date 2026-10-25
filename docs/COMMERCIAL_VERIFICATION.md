# 0.4 preview verification — October 24, 2026

This is an isolated development preview, not approval to replace the installed app or publish a release.

## Confirmed

- Swift 6.2.3, strict Swift 6 language mode: 195 tests in 33 suites passed in 6.706 seconds. Both test and optimized release builds used warnings-as-errors; no compiler warnings or errors were reported.
- Extracted preview distribution: 29 checks passed in 14.542 seconds, including signature, bundled dependencies, real images/PDFs/OCR, source integrity, and local LibreOffice. The verifier itself passed 7 tests.
- Independent reviews covered neural privacy, parser bounds, SVG resource rejection, real preview data, clipboard races, cancellation, and exact generated-file Undo inventory. Identified issues were fixed and regression tested.
- Native UI inspection covered light/dark wheel, onboarding, Sanitize review/add-region/export, notch/stash demo, compact orb/expiry, quality lens with real JPEG and HEIC encodes, and Impact metrics. The safe email/phone/IP fixture produced three review boxes; export produced a new 67 KB PNG from an 81 KB original.
- Actual lens measurements on the synthetic portrait: JPEG 250 KB → 28 KB; HEIC 250 KB → 16 KB; measured SSIM 99.8% for each at the displayed rounding.
- Original installed 0.3 executable SHA-256 stayed `77b8cfbae19e7370b53e215a91786066ee48f42f39f69437370b4a377fc6fb65`. Public checkout remained at `bd6e8d4553f5857d0a378ae22c6c71d9873ab869`.

## Initial failure retained in the evidence

The first package verification stopped after 21 checks with `TextRecognition.CRImageReaderError error 1` and a sandbox-extension diagnostic from macOS. Subsequent direct bundled/unbundled OCR probes succeeded, and the **same unchanged archive** passed all 29 checks on retry. Sampling showed Apple Espresso performing local AOT model compilation during the slow first runs. That is an observed correlation, not a proven root cause or a code fix. Cold-start OCR reliability must be checked again on clean target machines.

## Explicitly unverified release gates

- Physical double-Command, modifier drag, Spacebar-drag loupe, real orb hover/clipboard mutation and Finder notch drops on the new installed signed app. The isolated preview deliberately leaves global listeners with the installed 0.3 app. Earlier 0.3 checks do not certify 0.4.
- Multiple displays, hardware notch safe areas, Mission Control and full-screen interaction on real hardware; geometry has unit coverage.
- Actual screenshot-event delivery through Spotlight indexing; gate/stability logic has unit coverage.
- Full Xcode project build, light/dark `#Preview` canvas execution, App Intents metadata extraction, Shortcuts/Spotlight discovery and Finder Service registration. This machine has Command Line Tools only. The included Xcode project passes plist syntax validation; its build script explicitly rejects missing full-Xcode metadata tooling.
- Supported macOS/Intel matrix, Developer ID signing and notarization. This archive is Apple Silicon and ad-hoc signed.

PII detection remains best effort and always requires review. Originals remain intact. Frosted redaction is an opaque decorative replacement, not a blur of recoverable source pixels. Structured conversions intentionally reject unsupported/lossy structures; Swift reverse conversion produces placeholders.
