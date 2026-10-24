# Security policy

FileOrbit is an early preview. Only the newest preview is maintained; there is no security-response service-level guarantee.

## Reporting a vulnerability

Please use [GitHub's private vulnerability reporting](https://github.com/nikhilsainethi/FileOrbit/security/advisories/new) for suspected vulnerabilities. Include the affected version, macOS version, reproduction steps and a synthetic sample when possible. Do not open a public issue with exploit details or upload private documents.

## Processing and permissions

Conversions run locally. FileOrbit does not upload files, collect telemetry, or download converters in the background. LibreOffice is installed separately. The release includes checksum-pinned qpdf and resvg helpers and their license notices.

The Finder shortcut requires Accessibility permission to observe modifier-key gestures and Finder Automation permission to read the selected file. Manual file selection works without these permissions. Optional shortcut diagnostics are disabled by default and do not retain typed text or file contents.

The converters reject known unsupported or risky inputs and apply size, timeout and output-publication limits. These safeguards are not a guarantee that arbitrary untrusted documents are harmless. Keep macOS and LibreOffice updated, and report crashes or unexpected filesystem behavior privately.

Preview downloads are ad-hoc signed, not signed with an Apple Developer ID or notarized. Follow the [installation guide](docs/INSTALL.md), verify the published checksum, and use per-app macOS approval only if you trust this project. Do not disable Gatekeeper globally.
