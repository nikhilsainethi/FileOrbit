# FileOrbit approved design

Approved October 24, 2026. Local native macOS menu-bar utility. Select a file in Finder and double-tap Command to open a glass radial command center. No editing. No network conversion or telemetry.

Show file identity at center, relevant output formats around the wheel, compression via a small preset panel, processing/cancellation, actual result size, reveal in Finder. Escape and outside click dismiss when idle. Settings explain Accessibility and Finder Automation, dependency availability, and optional launch at login. Manual file picker and drag/drop remain usable without keyboard monitoring permission.

Native ImageIO handles runtime-supported raster encoders. PDFKit handles page render/text extraction; qpdf optimizes PDFs. resvg renders SVG. Installed LibreOffice handles DOCX/PPTX/TXT conversion using an isolated profile. DOCX compression selectively optimizes embedded images without an Office round-trip. No editable PDF-to-Office, OCR, vector tracing, editing, or upload features.

All outputs are validated in private temporary directories, originals remain unchanged, names never overwrite files, multi-page outputs use a distinct folder. Only retain compression results smaller than the source. Unsupported animation/multipage conversion must be rejected or explicitly handled, never silently discarded.

Initial packaged target macOS 15+ (the bundled qpdf binary requires 15), Apple Silicon build verified on this machine. Use native Liquid Glass on macOS 26+, vibrancy fallback otherwise. Public source is prepared locally; publication and Developer ID notarization are separate release steps.
