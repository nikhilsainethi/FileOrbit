# Commercial Local Engines Implementation Plan

> Required workflow: superpowers:subagent-driven-development with isolated module ownership, followed by spec and code review. Execute in this session under the user's implementation authorization.

**Goal:** Implement the approved commission as a safe, integrated native preview, preserving the verified 0.3 workflows.

**Architecture:** FileOrbitCore owns bounded value-oriented engines. MainActor coordinators own windows, UI state, clipboard and persisted aggregates. Existing conversion publishing and Finder gesture contracts remain intact.

**Tech Stack:** Swift 6, SwiftPM, AppKit, SwiftUI, Vision, CoreImage, NaturalLanguage, ImageIO, PDFKit, AppIntents; existing bundled helpers.

## Task 1 — Baseline and concurrency
- Files: Package.swift, existing Sources and Tests as required by compiler diagnostics.
- Run scripts/test.sh with the three FILEORBIT helper paths and /tmp/fileorbit-commercial-tests.
- Set swiftLanguageModes to v6, compile with -Xswiftc -warnings-as-errors; fix actor boundaries using value snapshots/Tasks instead of disabling checks.
- Re-run all existing tests; record baseline and migration results.

## Task 2 — Neural engine and review
- Create Core NeuralProcessingActor.swift, PIIDetector.swift and tests; App SanitizeReviewView.swift and tests.
- Define Sendable SubjectOutput, SanitizeStyle, PrivacyDetection, SanitizeDocument snapshot types.
- Test PII token matching, invalid inputs, region conversion, source freshness and permanent replacement first.
- Implement Vision subject extraction and OCR, reviewed export, collision-safe staging, both redaction styles.
- Tests must read real outputs, verify source preserved, text/metadata absent, cancel/failure cleanup.

## Task 3 — Spatial portal and observers
- Create App NotchPortalWindowController.swift, LiquidNotchView.swift, PasteboardSentinel.swift, ClipboardGlassOrbView.swift and model tests.
- Test global screen-origin geometry, pasteboard revision guard, self-write suppression, expiry generations and stash persistence first.
- Implement opt-in controllers with callback interfaces; root integrates into AppDelegate/FinderDragMonitor without replacing gesture detector.
- Use new observers only when enabled; preview demo is permission-free.

## Task 4 — Payload engines
- Create Core DeveloperPayloadEngine.swift and structured-data/design helper files plus tests.
- Test quoted CSV, Unicode, YAML safety, type preservation, Swift schemas, icon Contents.json, SVG rendering equivalence and color sampling.
- Engine uses own typed operations and returns ConversionResult; root supplies contextual wheel catalog.

## Task 5 — Processing integration and pipeline
- Modify AppModel.swift, OrbitInteraction.swift, OrbitView.swift, AppMain.swift and add CommercialCoordinator.swift/PipelineExecutor.swift.
- Route neural, review, developer operations through sub-ring commands; preserve existing file operations.
- Implement transactional favorite pipeline and explicit Clipboard Copy; tests validate only final publication and cancellation.

## Task 6 — Loupe and Impact
- Create Core ImagePreviewActor.swift/SSIM.swift; App SplitLoupePreviewView.swift, ImpactStore.swift, ImpactBentoView.swift.
- Test real codec bytes, decoded matching dimensions, SSIM identical/degraded fixtures, stale preview generation and metric accounting/Undo.
- Integrate Space down/up during Finder drag without taking focus; show real values, not hard-coded metrics.

## Task 7 — Onboarding and integration
- Create OnboardingSandboxWindow.swift and FileOrbitIntents.swift; extend SettingsView, Studio, build resources/scripts.
- Configure unique modifiers, real safe samples and routing, Accessibility/login controls.
- Verify AppIntents metadata/tool availability and Finder Services; report actual registration coverage.

## Task 8 — Review and delivery
- Independent spec review against BLUEPRINT and commission, then code-quality review.
- Run full Swift tests, warnings-as-errors release build and package checks; resolve regressions before claiming success.
- Launch isolated preview, inspect light/dark surfaces, test realistic synthetic fixtures, preserve installed app.
- Export preview/source archives, blueprint and evidence under outputs/FileOrbit-Commercial-Preview. No publishing/installing this new version without preview acceptance.
