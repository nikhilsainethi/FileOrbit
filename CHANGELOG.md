# Changelog

## 0.2.0-preview.1 — 2026-10-24

- Replace the rectangular command panel with a frameless floating glass wheel and rounded petals.
- Add the graphite-and-smoky-lavender dark palette and an app-only System/Light/Dark appearance setting.
- Keep compression at a predictable bottom position, with a three-preset wheel and compact processing/results.
- Use one active action for pointer and keyboard navigation; transparent gaps do not select an action.
- Improve Escape handling and screen placement, with geometry and placement regression tests.
- Preserve the local conversion engines, double-tap Command trigger and original-file protection.

This remains an ad-hoc-signed Apple Silicon preview, without Developer ID signing or notarization. Updated builds may need their macOS Accessibility permission refreshed.

## 0.1.0-preview.2 — 2026-10-24

First public preview for Apple Silicon Macs.

- Select a file in Finder and double-tap Command to open a native glass conversion wheel.
- Convert supported images, PDFs, DOCX, PPTX, TXT and static SVG files locally.
- Compress supported images, PDFs and DOCX embedded images without replacing originals.
- Use bundled qpdf/resvg helpers and optional, separately installed LibreOffice.
- Build with Swift Package Manager or use the shared `fileorbit-cli` conversion engine.
- Include source tests, packaged-app validation, dependency notices and installation/troubleshooting documentation.

This is an ad-hoc-signed preview, without Developer ID signing or Apple notarization. The download is for Apple Silicon. macOS 15 is the deployment target; see the [verification record](docs/TESTING.md) for platforms actually tested. Editable PDF-to-Office, OCR, editing, animation and batch conversion are not included.
