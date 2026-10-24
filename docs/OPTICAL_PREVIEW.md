# FileOrbit isolated optical glass preview

This is a separate native review app built from the same source as FileOrbit. It uses `io.fileorbit.preview`, separate preferences, and no global keyboard or Finder-drag listener. It does not replace `/Applications/FileOrbit.app`. All conversions are real and local; use sample copies while evaluating the design.

## Open and try it

Build with `scripts/fetch-helpers.sh` followed by `scripts/build-preview.sh /tmp/FileOrbit-optical-preview`. Open **FileOrbit Preview.app** in that folder. Choose one file to inspect it, or select several files for the shelf. In the installed production app, double-tap Command continues to use the original direct Finder selection flow.

- Click a format to convert. Hover over Compress, or PNG/JPG/WebP for a multipage PDF, for outer presets. Click a preset or drop a file directly onto it.
- Use the legend to switch Convert, Modify and Quick Actions. Arrow keys navigate; Return activates. Escape dismisses presets first, then the wheel.
- The hub shows a Quick Look thumbnail, actual size, and page count. Drop in the center or click it to collect files in Glass Shelf.
- The shelf accepts mixed file types, deduplicates them, and offers formats supported by every selected item. Each item reports success or failure. Cancel stops processing and preserves completed outputs.
- The activity pill shows actual before/after bytes. Hover for Quick Look, Copy Files, Reveal and Undo. Click the pill, then press Space for Quick Look. Undo is available only after unchanged-output verification and moves outputs to Trash; it never removes the source or an export folder containing user-added files.
- Open Studio from the menu-bar icon or the app menu. Drag one action onto another to reorder. The preview appearance selector affects only the configurator; App appearance controls the whole preview. Leave it on System to follow macOS. Recent history is session-only by default; persistence is opt-in.

## Document tools

OCR uses Apple Vision locally. Image metadata removal creates a PNG copy; PDF metadata removal removes the document Info dictionary, document-level XMP, and source trailer identifiers. It does not erase metadata inside retained annotations, attachments or embedded objects. Use redaction when content itself must be removed.

For Redact, draw rectangles on the displayed page, switch pages as needed, and save a separate copy. Rectangles can be removed individually or cleared on the current page. Export checks that the original has not changed since inspection. Closing or cancelling the editor invalidates pending export verification.

Redaction rebuilds every page from pixels (up to 144 DPI/16MP), so marked contents cannot be recovered by removing annotations. Searchable text, vectors, links, forms, attachments and source metadata are removed. Review the output before sharing. Digital-signature and encrypted input safeguards remain in force.

Compression presets are Light, Balanced and Extreme. They describe quality settings, not guaranteed percentage reductions. A compressed copy is saved only if it is smaller. Regular conversions, OCR and redaction may produce larger files.

## Included engines and limits

The preview bundles qpdf, resvg and a minimal cwebp 1.6.0 encoder built from pinned source with libpng 1.6.59. LibreOffice is installed separately for Office conversions. No helper is downloaded at app runtime. Missing engines hide their dependent actions.

The base wheel is 276 pt across (about 296 pt with active displacement). The optional outer presets extend to 384 pt before displacement. A larger transparent canvas reserves space for their shadows. Native macOS materials determine backdrop blur; no private blur APIs are used. Light/Dark follow macOS; Reduce Motion and Reduce Transparency are respected.

Target: macOS 15+; local validation: Apple Silicon on macOS 27.2. Intel and older macOS releases require separate verification. Physical Finder gestures were validated on the installed 0.3.0 candidate; see TESTING.md. The isolated preview deliberately cannot test its own global double-Command listener; it leaves the installed app’s listener alone. For installed-build observations, see TESTING.md. AirDrop opens the native recipient chooser; no recipient or transfer is selected automatically.

## Developer previews

Normal builds work with Swift 6.2/macOS 26 SDK Command Line Tools. In Xcode, add `FILEORBIT_XCODE_PREVIEWS` to Active Compilation Conditions to enable the Light/Dark `#Preview` scenes in `OrbitView.swift` and `LiquidGlassStyle.swift`. The wheel previews generate a small local PDF fixture. Xcode’s preview macros are excluded from normal CLT builds because that installation does not include the Xcode preview plugin.

Run `scripts/test.sh` with all four optional converter paths configured, then `python3 scripts/verify-package.py /path/to/preview.zip` for the extracted bundle. Package verification tests actual output content as well as signatures, licenses and helper resolution.
