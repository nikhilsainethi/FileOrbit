import AppKit
import SwiftUI
import FileOrbitCore

enum OrbitMode: String, CaseIterable, Identifiable {
    case convert, modify, quickActions
    var id: String { rawValue }
    var title: String { switch self { case .convert: return "Convert"; case .modify: return "Modify"; case .quickActions: return "Quick Actions" } }
    @MainActor var key: String { ModifierPreferences.shared.key(for: self) }
    @MainActor static func fromModifiers(_ flags: NSEvent.ModifierFlags) -> OrbitMode? { ModifierPreferences.shared.mode(for: flags) }

}
enum OrbitCommand: Equatable {
    case liftSubject(SubjectOutput, copy: Bool), sanitize(SanitizeStyle), developer(DeveloperOperation)
    case file(FileOperation), redact, shelf, airDrop, copyPath, terminal
}
struct OrbitAction: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let subtitle: String
    let command: OrbitCommand
    init(id: String, title: String, symbol: String, subtitle: String, command: OrbitCommand) {
        self.id = id; self.title = title; self.symbol = symbol; self.subtitle = subtitle; self.command = command
    }
    init(_ action: FileAction) {
        self.init(id: action.id, title: action.title, symbol: action.symbol, subtitle: action.subtitle,
                  command: action.operation == .redactPDF([]) ? .redact : .file(action.operation))
    }
    var isCompression: Bool { if case .file(.compress) = command { return true }; return false }
    var descriptor: StudioActionDescriptor { StudioActionDescriptor(id: id, title: title, symbol: symbol) }
}
struct OrbitParameter: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let command: OrbitCommand
    var operation: FileOperation? { if case .file(let value) = command { return value }; return nil }
    init(id: String, title: String, subtitle: String, operation: FileOperation) {
        self.id = id; self.title = title; self.subtitle = subtitle; command = .file(operation)
    }
    init(id: String, title: String, subtitle: String, command: OrbitCommand) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.command = command
    }
    static func options(for action: OrbitAction, kind: FileKind, pageCount: Int?) -> [OrbitParameter] {
        switch action.command {
        case .liftSubject:
            return [.init(id: "transparent", title: "Transparent", subtitle: "PNG with alpha", command: .liftSubject(.transparentPNG, copy: false)),
                    .init(id: "sticker", title: "Copy Sticker", subtitle: "PNG to clipboard", command: .liftSubject(.transparentPNG, copy: true)),
                    .init(id: "white", title: "White Studio", subtitle: "Opaque backdrop", command: .liftSubject(.whiteBackdrop, copy: false))]
        case .sanitize:
            return [.init(id: "frosted", title: "Frosted Glass", subtitle: "Review then remove", command: .sanitize(.frosted)),
                    .init(id: "obsidian", title: "Solid Obsidian", subtitle: "Review then remove", command: .sanitize(.obsidian))]
        case .file(.compress):
            return [
                .init(id: "gentle", title: "Light", subtitle: "Higher quality", operation: .compress(.gentle)),
                .init(id: "balanced", title: "Balanced", subtitle: "Quality + size", operation: .compress(.balanced)),
                .init(id: "small", title: "Extreme", subtitle: "Lower resolution", operation: .compress(.small))
            ]
        case .file(.convert(let format)) where kind == .pdf && (pageCount ?? 0) > 1 && [.png, .jpg, .webp].contains(format):
            return [
                .init(id: "first", title: "First page", subtitle: "One image", operation: .exportPDF(format, .firstPage)),
                .init(id: "all", title: "All pages", subtitle: "New folder", operation: .exportPDF(format, .allPages)),
                .init(id: "tall", title: "Tall image", subtitle: "Merged vertically", operation: .exportPDF(format, .mergedTallImage))
            ]
        default: return []
        }
    }
}
struct OrbitParameterLayout {
    let parentAngle: Double
    let count: Int
    var span: Double { min(40, 120 / Double(max(1, count))) }
    func angle(_ index: Int) -> Double { parentAngle + (Double(index) - Double(count - 1) / 2) * span }
    func shape(_ index: Int) -> AnnularWedgeShape {
        AnnularWedgeShape(centerAngle: angle(index), span: span,
                          innerRadius: OrbitLayout.secondaryInnerRadius, outerRadius: OrbitLayout.secondaryOuterRadius)
    }
    func path(_ index: Int, activeIndex: Int?) -> Path {
        let base = shape(index).path(in: CGRect(origin: .zero, size: OrbitLayout.wheelFrame.size))
        return activeIndex == index ? base.applying(OrbitLayout.activeTransform(angle: angle(index))) : base
    }
    func index(at point: CGPoint, activeIndex: Int?) -> Int? {
        if let activeIndex, (0..<count).contains(activeIndex), path(activeIndex, activeIndex: activeIndex).contains(point) { return activeIndex }
        return (0..<count).first { $0 != activeIndex && path($0, activeIndex: activeIndex).contains(point) }
    }
}
