import Foundation

public enum FileKind: String, Sendable { case image, pdf, docx, pptx, text, svg, unsupported }
public enum OutputFormat: String, CaseIterable, Sendable { case png, jpg, heic, tiff, pdf, txt, docx }
public enum CompressionPreset: String, CaseIterable, Sendable { case gentle, balanced, small }
public enum FileOperation: Equatable, Sendable {
    case convert(OutputFormat)
    case compress(CompressionPreset)
}

public struct ConversionRequest: Sendable {
    public let input: URL
    public let operation: FileOperation
    public let outputDirectory: URL?
    public init(input: URL, operation: FileOperation, outputDirectory: URL? = nil) {
        self.input = input; self.operation = operation; self.outputDirectory = outputDirectory
    }
}

public struct ConversionResult: Sendable {
    public let outputURLs: [URL]
    public let inputBytes: Int64
    public let outputBytes: Int64
    public let note: String?
    public init(outputURLs: [URL], inputBytes: Int64, outputBytes: Int64, note: String? = nil) {
        self.outputURLs = outputURLs; self.inputBytes = inputBytes; self.outputBytes = outputBytes; self.note = note
    }
}

public enum ConversionError: LocalizedError {
    case unsupported(String), invalidInput(String), missingDependency(String), failed(String), cancelled, notSmaller
    public var errorDescription: String? {
        switch self {
        case .unsupported(let s), .invalidInput(let s), .missingDependency(let s), .failed(let s): return s
        case .cancelled: return "Conversion cancelled. Your original file is unchanged."
        case .notSmaller: return "This file is already compact at this setting. No larger copy was saved."
        }
    }
}

public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func check() throws { if isCancelled { throw ConversionError.cancelled } }
}

public struct EngineEnvironment: Sendable {
    public let libreOfficeURL: URL?
    public let qpdfURL: URL?
    public let resvgURL: URL?
    public init(libreOfficeURL: URL? = nil, qpdfURL: URL? = nil, resvgURL: URL? = nil) {
        self.libreOfficeURL = libreOfficeURL; self.qpdfURL = qpdfURL; self.resvgURL = resvgURL
    }
}

public struct FileAction: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbol: String
    public let operation: FileOperation
    public init(id: String, title: String, subtitle: String, symbol: String, operation: FileOperation) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.symbol = symbol; self.operation = operation
    }
}
