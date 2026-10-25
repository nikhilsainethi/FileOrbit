# FileOrbit 0.4 local preview

This development preview adds the commercial feature blueprint in `docs/plans/2026-10-24-commercial-blueprint.md`. It is not a notarized public release. The installed 0.3 app and public GitHub release are not changed by building or running the separate preview.

## Try the native UI

Build with `scripts/build-preview.sh /tmp/FileOrbit-commercial-preview` (choose a fresh directory). Launch **FileOrbit Preview.app** from that directory. It has a separate bundle identifier and preference domain. Global Finder keyboard/drag listeners stay with your installed app.

1. Start in the 680×460 onboarding sandbox. Drag a synthetic Portrait/Deck card onto the real wheel or click **Open practice wheel**. Outputs go into the practice folder. Click a format or use the arrow keys and Return.
2. Use **Modify → Lift Subject** for transparent PNG, Copy Sticker, or white backdrop. Apple Vision runs locally. The hub shimmers while processing.
3. Use **Modify → Sanitize**. Choose a style, review every page, add/remove boxes, and check the review acknowledgment before saving. Both styles permanently replace covered pixels. The frosted replacement does not blur the original secret. Detection is best effort, not a privacy guarantee. PDF export removes searchable text/vector data across every page.
4. In Settings, **Preview Liquid Notch** opens the two-zone portal. Drop a sample on the left to keep a reference, or on the right to run the selected image pipeline. Original files do not move. Clipboard-only pins are managed local copies; removing those pins deletes their managed copies.
5. Preview Settings also has **Try clipboard orb** and **Preview quality loupe**, using synthetic images without enabling background observers. A real orb action intentionally changes the clipboard. The loupe reports actual encoded size and measured full-image sampled luminance SSIM; the 200% center crop shows aligned source/output pixels.
6. Open Studio to inspect the Impact bento. “Smaller outputs” is output-size reduction, not disk space freed, because originals stay intact. Time saved is labelled as an estimate at 20 seconds per completed file. Share only copies/saves a card; it does not post anywhere.

Choose System, Light or Dark in Studio. All new surfaces share the quartz/slate glass theme and respect Reduce Motion/Reduce Transparency. Background Notch, clipboard and screenshot observers default off. When enabled, screenshot detection depends on Spotlight indexing/access; no screen recording is requested.

## Developer and designer tools

- JSON, a bounded JSON-compatible YAML subset, CSV and generated Swift Codable schemas have contextual conversion wedges.
- CSV accepts flat rectangular records and preserves strings; nested/null/unequal data is rejected instead of discarded.
- Swift files are accepted only in the constrained generated schema format. Reverse conversion creates a placeholder template, not recovered original values. Nothing executes Swift input.
- SVG minification conservatively removes legal separators without rounding coordinates. External/active content and unsupported CSS are rejected.
- App Icons produces a real macOS `.appiconset`: ten 1×/2× slots from 16 to 1024px. macOS has no 3× icon slot. Input must be square and at least 1024px. Undo removes captured generated files while leaving their folder and any later user additions intact.
- Palette writes a swatch PNG plus hex/SwiftUI text and explicitly copies the card. Transparent pixels do not count as dominant colors.

Developer tools cap input at 64 MB, structured text at 8 MB / 48 levels / 100,000 values, with additional schema work/width limits. Neural review caps pages, rendered pixels, and snapshot bytes. Unsupported or excessive inputs report errors rather than silently dropping data.

## Shortcuts, Spotlight and Finder Services

The source includes real App Intents for local image conversion/compression/subject isolation and an App Shortcuts provider. These return new files, not modifications to their inputs. Sanitize is deliberately reviewed in the app.

**Important tooling status:** a SwiftPM/Command Line Tools build compiles the intent implementations but does not emit the metadata required for Shortcuts/Spotlight discovery. Do not treat compilation as registration verification.

With full Xcode 26.2 or newer selected, run:

```sh
./scripts/build-xcode-app.sh /tmp/fileorbit-xcode
```

The included `FileOrbit.xcodeproj` references the local FileOrbitCore package and lets Xcode perform metadata extraction. The script fails if `Metadata.appintents` is absent. Its native app target also registers **Services → Open in FileOrbit** for Finder selections. The isolated preview deliberately removes that registration so it cannot replace the installed handler. Full Xcode project execution, metadata discovery and Shortcuts/Spotlight UI registration have not been verified on this CLT-only development Mac. Run and verify them before a public release. Xcode builds use locally available helper tools; the SwiftPM distribution script bundles helpers from `FILEORBIT_VENDOR_DIR`.

To make a transformation a Finder Quick Action after registration, add its FileOrbit action to a Shortcut, accept files as input, and enable **Use as Quick Action → Finder** in Shortcuts. Save/return the resulting IntentFile explicitly in that Shortcut.

Debug Xcode builds enable `FILEORBIT_XCODE_PREVIEWS`. Each new public SwiftUI surface has light/dark preview coverage; the loupe and Sanitize previews use safe local samples. Xcode preview execution suppresses production permission/login controls.

## Verification and release gates

See the delivered Verification report for the exact tested commit and counts. Source tests include real Vision OCR/segmentation, both irreversible fills, PDF text/metadata removal, native key-event safety, clipboard revision guards, cancellation, schema and SVG safety, actual SVG rendering equivalence, Swift schema compilation, real encoded-preview equivalence, SSIM, original preservation and impact/Undo accounting.

On this development Mac, the first packaged OCR check failed with Apple TextRecognition error 1 while local model compilation was occurring. Both direct OCR probes and the unchanged full package passed on retry. Cold-start behavior remains part of release validation; a retry is not evidence that the first-run issue was fixed.

Before publication: validate physical Finder gestures on the new signed build, cross-display/full-screen/Spaces transitions, screenshot notifications on the target Mac, full-Xcode metadata/canvas, supported macOS/architecture matrix, Developer ID signing/notarization and distribution. Existing 0.3 physical checks do not substitute for those new-build checks. Local development uses ad-hoc signing; never describe it as notarized or commercially certified.
