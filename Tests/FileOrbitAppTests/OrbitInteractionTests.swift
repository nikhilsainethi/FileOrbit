import Foundation
import AppKit
import Testing
import FileOrbitCore
@testable import FileOrbit

@MainActor struct OrbitInteractionTests {
    @Test func parametersDoNotPromiseAnInventedSavingsPercentage() {
        let action = OrbitAction(id: "compress", title: "Compress", symbol: "arrow.down", subtitle: "Reduce size", command: .file(.compress(.balanced)))
        let options = OrbitParameter.options(for: action, kind: .image, pageCount: nil)
        #expect(options.map(\.title) == ["Light", "Balanced", "Extreme"])
        #expect(options.map(\.operation) == [.compress(.gentle), .compress(.balanced), .compress(.small)])
        #expect(options.allSatisfy { !$0.subtitle.contains("%") })
    }
    @Test func pdfParametersOnlyAppearForMultipageImageExports() {
        let image = OrbitAction(id: "convert-png", title: "PNG", symbol: "photo", subtitle: "Image", command: .file(.convert(.png)))
        #expect(OrbitParameter.options(for: image, kind: .pdf, pageCount: 3).map(\.operation) == [.exportPDF(.png, .firstPage), .exportPDF(.png, .allPages), .exportPDF(.png, .mergedTallImage)])
        #expect(OrbitParameter.options(for: image, kind: .pdf, pageCount: 1).isEmpty)
        #expect(OrbitParameter.options(for: image, kind: .image, pageCount: nil).isEmpty)
    }
    @Test func modifierModesIgnoreCommandChords() {
        #expect(OrbitMode.fromModifiers(.shift) == .convert)
        #expect(OrbitMode.fromModifiers(.option) == .modify)
        #expect(OrbitMode.fromModifiers(.control) == .quickActions)
        #expect(OrbitMode.fromModifiers([.command, .option]) == nil)
        #expect(OrbitMode.fromModifiers([]) == nil)
    }
    @Test func secondaryArcHitTestingRejectsMoatAndMatchesTransformedPetals() {
        let layout = OrbitParameterLayout(parentAngle: 90, count: 3)
        #expect(layout.index(at: OrbitLayout.polar(radius: 169, degrees: 90, center: OrbitLayout.wheelCenter), activeIndex: nil) == 1)
        #expect(layout.index(at: OrbitLayout.polar(radius: 142, degrees: 90, center: OrbitLayout.wheelCenter), activeIndex: nil) == nil)
        let boundary = OrbitLayout.polar(radius: 169, degrees: 90 + layout.span / 2, center: OrbitLayout.wheelCenter)
        #expect(layout.index(at: boundary, activeIndex: nil) == nil)
        let activeTip = OrbitLayout.polar(radius: 199, degrees: 90, center: OrbitLayout.wheelCenter)
        #expect(layout.index(at: activeTip, activeIndex: 1) == 1)
        #expect(layout.index(at: activeTip, activeIndex: nil) == nil)
    }
    @Test func invalidSourceResetsSelectionAndSubring() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("input.txt")
        try Data("hello".utf8).write(to: file)
        let model = AppModel()
        model.select(file)
        model.mode = .quickActions
        #expect(model.orbitActions.count == 4)
        model.selectionFailed("No selection")
        #expect(model.orbitActions.isEmpty)
        #expect(model.selectedActionID == nil)
        #expect(model.parameterParentID == nil)
    }
}
