# FileOrbit Implementation Plan

> Execute in this session with the subagent-driven-development workflow and independent spec/code review.

**Goal:** Deliver a runnable native local macOS app with double-tap Command, glass wheel, tested conversions and compression.

**Architecture:** SwiftPM core library isolates capability selection, trigger state machine and conversion adapters from the AppKit/SwiftUI app. Synchronous adapters execute on a background queue, take cancellation tokens, use argument arrays for processes, validate staged outputs, and publish to collision-safe paths.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode; AppKit, SwiftUI, ImageIO, CoreGraphics, PDFKit, Foundation XML, installed LibreOffice/qpdf/resvg; Swift Testing (selected after verifying the standalone Command Line Tools do not include XCTest).

## Task 1: Contracts, trigger, capabilities
Files: Sources/FileOrbitCore/Models.swift, DoubleCommandDetector.swift, Capabilities.swift; Tests/FileOrbitCoreTests/TriggerTests.swift and CapabilityTests.swift.
Write failing tests for two clean press/release cycles, timeout, chords, competing modifiers, mouse clicks, long hold and reset. Implement deterministic timestamp-driven trigger. Capability actions must match installed engines and native encoders. Run `swift test --filter TriggerTests` and `--filter CapabilityTests`.

## Task 2: Native processing and safe publication
Files: Sources/FileOrbitCore/ConversionEngine.swift, NativeConverter.swift, OutputPublisher.swift; corresponding tests.
Write fixture tests before functionality: valid raster conversion, alpha to JPEG background, orientation, multipage rejection, PDF rendering/text, empty/corrupt input, name collision, compression-not-smaller and cancellation. Implement ImageIO/PDFKit plus qpdf/resvg adapters. Reopen outputs, assert dimensions/page count and source bytes unchanged. Run `swift test`.

## Task 3: Office, subprocesses, DOCX compression
Files: Sources/FileOrbitCore/OfficeConverter.swift, DocxCompressor.swift, LocalProcess.swift; corresponding tests.
First test process timeout/cancellation and literal filenames, safe ZIP extraction and DOCX image preservation. LibreOffice uses private profiles and explicit output filters. DOCX extraction validates names/symlinks/size/count before rebuilding. Reopen packages and compare relationships/XML; fixture Office tests validate PDF page count/text and image output. Run targeted tests then all tests.

## Task 4: Native app and CLI
Files: Sources/FileOrbit/AppMain.swift, AppModel.swift, OrbitView.swift, SettingsView.swift, FinderSelection.swift, CommandMonitor.swift; Sources/FileOrbitCLI/main.swift.
Build status item, nonactivating floating NSPanel, glass radial segments, file drop/picker, settings, progress/result/error states. Capture Finder selection before activating panel, refuse stale Finder selection when another app is frontmost. Never prompt for permissions until the user chooses Enable. Trigger has no keyboard content logging. CLI exercises exactly the production engine.

## Task 5: Packaging, integration and review
Files: scripts/build-app.sh, scripts/install-dependencies.sh, Resources/Info.plist, README.md, LICENSE, docs/TESTING.md.
Create ad-hoc-signed .app and ZIP, dependency instructions, release notes and honest limitations. Run release build, full tests, representative real converters and source-integrity checks. Inspect app via native UI automation. Independently review spec, then code quality; resolve substantive issues with regression tests. Verify signature, bundle launch, git diff whitespace, then commit. Record which live OS permission interactions remain user-gated.
