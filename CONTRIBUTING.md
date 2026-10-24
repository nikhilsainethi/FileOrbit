# Contributing to FileOrbit

Bug reports, documentation improvements and focused pull requests are welcome. For a feature that changes supported formats or the Finder interaction, open an issue first so its behavior and limits can be discussed.

## Development

Use a Mac with Swift 6.2 or later and the macOS 26 SDK or later. Install LibreOffice for Office conversion tests. Download the pinned SVG/PDF helpers, then run the tests:

```sh
./scripts/fetch-helpers.sh
FILEORBIT_QPDF="$PWD/.build/vendor/qpdf/bin/qpdf" \
FILEORBIT_RESVG="$PWD/.build/vendor/resvg/resvg" \
./scripts/test.sh
./scripts/build-app.sh
python3 scripts/verify-package.py dist/FileOrbit-macOS-$(uname -m).zip
```

The package verifier returns exit code 3 when a required integration dependency is unavailable. Report skipped coverage rather than treating it as a complete pass. GitHub Actions runs the tests and package verifier on Apple Silicon macOS 26.

## Changes and testing

- Keep conversion local and preserve original files. Never overwrite an existing output.
- Show only actions the current file and installed engines support.
- Bound memory, subprocess time and temporary storage. Treat document contents as untrusted data.
- Add regression tests for conversion, cancellation or shortcut behavior changes. UI-only fixes should include clear manual verification steps.
- Verify the actual packaged app when changing helpers, resources or signing.
- Keep license notices current when changing bundled dependencies.

Use synthetic or freely licensed fixtures. Do not commit personal documents, credentials, local logs, generated app bundles or build outputs. Diagnostic logs must not capture typed text, file contents or file paths.

In pull requests, explain the problem, resulting behavior, tests performed and any known limitations. The project currently ships an ad-hoc-signed preview; changing a local build can require reauthorizing its Accessibility permission. See [installation and troubleshooting](docs/INSTALL.md).

## Reporting problems

Include the macOS version, Apple Silicon/Intel architecture, FileOrbit version, file format, operation, and exact error message. Start with a small synthetic reproduction; do not post private source files. Report security vulnerabilities using [SECURITY.md](SECURITY.md).

Contributions are made under the repository's [MIT license](LICENSE).
