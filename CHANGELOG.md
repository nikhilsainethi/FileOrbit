# Changelog

## 0.1.0-preview.2 — 2026-10-24

First public preview for Apple Silicon Macs.

- Select a file in Finder and double-tap Command to open a native glass conversion wheel.
- Convert supported images, PDFs, DOCX, PPTX, TXT and static SVG files locally.
- Compress supported images, PDFs and DOCX embedded images without replacing originals.
- Use bundled qpdf/resvg helpers and optional, separately installed LibreOffice.
- Build with Swift Package Manager or use the shared `fileorbit-cli` conversion engine.
- Include source tests, packaged-app validation, dependency notices and installation/troubleshooting documentation.

This is an ad-hoc-signed preview, without Developer ID signing or Apple notarization. The download is for Apple Silicon. macOS 15 is the deployment target; see the [verification record](docs/TESTING.md) for platforms actually tested. Editable PDF-to-Office, OCR, editing, animation and batch conversion are not included.
