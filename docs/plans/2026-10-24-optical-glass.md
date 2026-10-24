# Optical Glass Studio Implementation Plan

> **For implementers:** Use the executing-plans, test-driven-development, and verification-before-completion workflows. Independent file ownership permits parallel component work; integration and reviews remain sequential.

**Goal:** Deliver a compilable, isolated FileOrbit preview with compact optical glass geometry, direct radial/drop interactions, contextual presets, local document tools, batch shelf, completion HUD, and customization studio.

**Architecture:** Preserve the existing transactional conversion engine and double-Command recognizer. Add tested core operations and stateful AppKit/SwiftUI presentation components. All outputs remain separate copies; no network processing, fabricated savings, or placeholder actions.

**Tech stack:** Swift 6.2 (Swift 5 language mode), SwiftUI, AppKit, ImageIO, PDFKit, Vision, QuickLookThumbnailing, existing qpdf/resvg/LibreOffice.

## Design decisions and audit

- Source baseline: `7d44636`, approved/public 0.2.0-preview.1. Installed app and public release remain unchanged for this new preview.
- `OrbitGeometry.swift:5-9` uses a 410 pt wheel and 166 pt hub. Line 21 subtracts seven degrees for gaps. Lines 74-86 approximate corners with quadratic curves.
- `OrbitView.swift:380-409` combines native glass tint and a shared shadow. There is no explicit inner-shadow implementation; replace the material treatment instead of attributing a nonexistent inner-shadow function.
- `OrbitView.swift:134-138` uses a generic icon and two-line filename. Lines 54-59 only select a single dropped URL.
- `AppMain.swift:156-177` already provides a transparent native panel. `CommandMonitor.swift` has no drag-session state.
- Main radii: hub 52, inner 60, outer 138; expanded parameter ring 146...192. Base visible footprint remains under 310 pt; the expanded ring necessarily exceeds it. Canvas reserves space for animation without a rectangular backing.
- Gaps are parallel offsets of each radial boundary by 3 pt. Fillet centers satisfy both the offset-line distance and concentric-circle tangency, with separate outer 14 pt and inner 10 pt radii.
- Use active, behind-window native visual-effect material with adaptive surface washes/rims; public AppKit controls the actual blur radius. Do not apply foreground Gaussian blur to labels or use private blur APIs.
- Light/Dark follow macOS by default, retaining an app-only override. Honor Reduce Motion/Transparency, keyboard navigation, and accessible labels.
- Preset labels are Light/Balanced/Extreme; descriptions state quality behavior. Fixed -25/-55/-80 percent savings are not promises or fabricated estimates. The hub shows actual metadata or the selected action; results show measured bytes.
- Redact uses manually drawn normalized page regions (user confirmed). Output is a rasterized separate PDF with content burned out, not removable black annotations; disclose loss of searchable/vector content.
- History is local and session-scoped by default, with opt-in persistence and a clear-history control. Undo trashes only unchanged app-created outputs, never source files or edited outputs.

## Task 1 — Geometry and glass design system

Files: `Sources/FileOrbit/OrbitGeometry.swift`, new `LiquidGlassStyle.swift`, geometry/placement tests.

1. Add failing tests for constant-width gaps, tangent fillets, valid paths at 1...7 actions, moat/radii, and hit testing after hover displacement.
2. Implement `AnnularWedgeShape(centerAngle:span:innerRadius:outerRadius:gap:outerCornerRadius:innerCornerRadius:)` and compact `OrbitLayout`. Shared rendering/hit-testing paths must agree.
3. Preserve convenient `OrbitPetal` compatibility while integration proceeds. Expose layout canvas/center and primary/secondary radii.
4. Implement `LiquidGlassStyle<S: Shape>` with active native backdrop, adaptive washes/rims, requested shadows, and opaque accessibility fallback. Expose palette helpers.
5. Run targeted geometry tests and inspect light/dark native previews after integration.

## Task 2 — Real document/image operations

Files: core models/capabilities/conversion engine/native converter, new document-tool adapters, CLI switches, core tests. No GUI edits.

Interfaces: `PDFExportMode` = firstPage/allPages/mergedTallImage; `RedactionRegion(pageIndex:normalizedRect:)` uses normalized top-left displayed-page coordinates; `FileOperation` adds `exportPDF(OutputFormat, PDFExportMode)`, `scrubMetadata`, `splitPDF`, `ocrText`, `redactPDF([RedactionRegion])`. Add WebP output where a real available encoder supports it; unsupported formats must not be advertised.

1. Write real fixture tests for PDF export variants, split page content, OCR, metadata removal, and nonrecoverable redaction while preserving source hashes.
2. Extend the transactional staging/validation/publication flow; maintain cancellation and signed/encrypted input safeguards. Bound all image allocations and page counts.
3. Use Vision OCR locally. Re-encode metadata-scrubbed images; remove standard PDF document metadata and XMP with explicit limits. Redaction must rasterize pages and burn regions into pixels.
4. Verify all generated files reopen, PDF rotations/regions align, cancelled operations publish nothing, and filename collisions remain safe.

## Task 3 — Independent auxiliary presentation components

Files: new `FileInspector.swift`, `GlassShelfModel.swift`, `FloatingGlassShelfView.swift`, `JobHUDModel.swift`, `TransientHUDToastView.swift`, `StudioPreferences.swift`, `MenuBarStudioPopover.swift`, supporting tests. No edits to AppMain/AppModel/OrbitView or core.

1. Async cancellable QL thumbnails and actual file size/page/frame metadata; prevent stale-thumbnail races.
2. Shelf accepts heterogeneous local files, deduplicates entries, exposes available common operations, serially processes a cancellable batch, and reports each outcome without hiding failures.
3. HUD displays real progress when known and indeterminate progress otherwise; completed sizes are measured. Implement Quick Look, file-URL copy, reveal, and safe undo callbacks.
4. Local recent history and persisted custom action order/appearance preferences. Studio provides real radial drag-and-drop reordering, live appearance previews, and history controls.
5. Tests cover batch capability handling, partial failure/cancellation, safe undo refusing edited outputs, and order persistence without losing newly available actions.

## Task 4 — Integrate radial interaction state and hub

Files: `AppModel.swift`, `OrbitView.swift`, new radial action/state types, redaction preview, native drop target, tests.

1. Preserve old model methods/tests while adding Convert/Modify/Quick Actions and capability-aware action descriptors.
2. Render compact wedges, QL inspector, 6 pt spring displacement/1.03 scale, hierarchical SF Symbols/bounce, and single selection source for pointer/keyboard.
3. Reveal outer parameter arcs after 160 ms; cancel stale hover tasks, keep arcs open across the moat, and haptically acknowledge actual selection changes.
4. Add primary/secondary hit testing and native drop routing: wedge executes, preset executes exact choice, center collects in shelf, gap cancels. Multiple files route to batch shelf.
5. Implement interactive mode legend, modifier latching during drags, and manual region-selection redaction UI backed by the real core operation.

## Task 5 — Native windows, drag entry, and system routes

Files: `AppMain.swift`, new drag monitor/window coordinator as needed, existing Settings updates.

1. Keep double-Command selection unchanged; add a separate Finder drag-session monitor that observes modifier changes without swallowing normal shortcuts.
2. Show/hide the wheel around the pointer without edge clipping; support drag-destination handoff and Escape. The isolated preview never requests Accessibility or steals the installed app's global trigger.
3. Add a floating 300x54 completion/progress panel, 240x280 movable/pinnable shelf, and native menu-bar studio popover.
4. Route AirDrop through its native chooser, copy path explicitly, and open the source directory in Terminal without interpolating shell commands.
5. Animate drop completion and shelf presentation; honor reduced-motion settings.

## Task 6 — Preview, audit, and delivery

1. Supply Light/Dark `#Preview` examples behind an explicit preview compiler flag if the standalone CLT lacks Xcode preview macros. Normal builds must compile without Xcode; document how to enable Xcode previews.
2. Run complete tests with qpdf/resvg/LibreOffice. Add preview-package checks for new behavior; build and verify the separate preview ZIP.
3. Perform independent specification review, then quality/security review; resolve defects and re-run affected checks.
4. Inspect native light/dark wheel, expanded arcs, redaction preview, HUD, shelf, and studio. Test pointer/keyboard/drop interactions and original-file integrity using safe fixtures.
5. Deliver the preview app, screenshots, readable instructions and verification limits under `outputs/`. Ask for review before installing over the current app or publishing this upgrade.

## Verification commands

`FILEORBIT_QPDF=<workspace>/work/tools/qpdf/bin/qpdf FILEORBIT_RESVG=<workspace>/work/tools/resvg/resvg ./scripts/test.sh --scratch-path /tmp/fileorbit-optical-tests`

`FILEORBIT_BUILD_DIR=/tmp/fileorbit-optical-release FILEORBIT_VENDOR_DIR=<workspace>/work/tools ./scripts/build-preview.sh <new-system-temporary-output-directory>`

Every claim of successful conversion, safe redaction, undo, or release readiness requires observed test evidence. Preview-only compilation and supported-platform limits must remain explicit.
