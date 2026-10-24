# Frameless Glass Wheel Implementation Plan

> **For Claude:** Use superpowers:subagent-driven-development to implement the approved design in this session.

**Goal:** Build a working, isolated native preview of the frameless glass wheel for user approval before publishing any change.

**Architecture:** Keep conversion and Finder shortcut behavior intact. Replace the rectangular SwiftUI surface with separated rounded glass petals and a small file hub. Use an independent preview bundle identity and disable global shortcut monitoring in that preview so the installed app keeps its permissions and behavior.

**Tech Stack:** SwiftUI, AppKit NSPanel, native macOS 26 Liquid Glass with macOS 15 material fallback, Swift Testing.

## Approved design
- Transparent exterior and gaps; no rectangular card, header, tagline, footer, or uploader on the selected-file path.
- Approximately 410-point orbit with rounded petals, readable labels, one teal active selection, subtle adaptive glass, and a compact file hub.
- Show only actual supported conversions/compression; preserve 2–7 action layouts.
- Compression uses three selectable presets and a clear central action. Progress/result/error surfaces remain compact and readable.
- Preserve keyboard arrows/Return/Escape, pointer actions, accessible names, reduced transparency/motion, menu-bar settings, manual selection, cancellation, safe outputs, and Finder reveal.
- The user must approve the real preview before GitHub changes or replacing the installed app.

## Task 1: Baseline and isolation
1. Create branch `ui/frameless-glass` in `work/FileOrbit-glass-preview` from public main.
2. Run `FILEORBIT_QPDF=/Applications/FileOrbit.app/Contents/Helpers/qpdf/bin/qpdf FILEORBIT_RESVG=/Applications/FileOrbit.app/Contents/Helpers/resvg ./scripts/test.sh --scratch-path /tmp/fileorbit-glass-tests` and require all baseline tests pass.
3. Record installed app executable hash and main HEAD; preserve both throughout preview work.

## Task 2: Native orbit views
**Files:** `Sources/FileOrbit/OrbitView.swift`, new `Sources/FileOrbit/OrbitGeometry.swift`, relevant `Tests/FileOrbitAppTests/OrbitGeometryTests.swift`.
1. Centralize rounded petal geometry and keyboard selection handling, sharing the shape for drawing/content hit-testing.
2. Add meaningful geometry/selection boundary tests first, verify failure, implement, and rerun.
3. Build the selected-file orbit, compact hub and active-caption pill, using one active index for both hover and keyboard.
4. Build compression preset orbit, compact progress, result, and empty/unsupported/error surfaces. Preserve real model actions and full error messages.
5. Respect reduced motion/transparency and native adaptive light/dark contrast. Test compilation before integration.

## Task 3: Window and preview packaging
**Files:** `Sources/FileOrbit/AppMain.swift`, new `scripts/build-preview.sh` and any focused app tests.
1. Fit the transparent panel to the new view; remove rectangular native shadow; preserve screen clamping and Finder selection before activation.
2. Verify transparent space click behavior on the real app, including dismissal and busy-stage behavior; use the least intrusive correct native approach.
3. Add an isolated preview mode identified by bundle metadata. It must not register the global shortcut, change the installed app, or share its preferences.
4. Package preview separately as `FileOrbit Preview.app` with bundle ID `io.fileorbit.preview`, retaining the real conversion engine and helper notices. Never overwrite public artifacts.

## Task 4: Integration verification
1. Run complete source tests with bundled qpdf/resvg and installed LibreOffice.
2. Build the production-shaped package into a private scratch directory and run `python3 scripts/verify-package.py <archive>`; require all 19 checks.
3. Build/launch the separate preview against a copied safe fixture, so conversions only create files in preview samples.
4. Exercise real image conversion, compression, result, reveal, keyboard, dismissal, unsupported files, and low-action document/PDF layouts. Inspect screenshots for clipping, glare and legibility; check a forced preview light/dark appearance without changing system settings.
5. Review spec compliance, then code quality; resolve substantive findings before delivery.
6. Save screenshots and preview package under `outputs/FileOrbit-Glass-Preview/`, open the preview for the user, report verified limits, and ask for design approval. Do not push or publish.
