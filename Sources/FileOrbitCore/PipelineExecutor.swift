import Foundation

public enum PinnedPipeline: String, CaseIterable, Sendable {
    case optimizeWebP = "optimize-webp-copy", png = "png", compress = "compress"
    public var title: String {
        switch self { case .optimizeWebP: return "Optimize → WebP → Copy"; case .png: return "PNG → Copy"; case .compress: return "Compress → Copy" }
    }
    public var copiesToClipboard: Bool { true }
}

/// Intermediate conversion files remain inside the private workspace. Only the final file is published.
public struct PipelineExecutor: Sendable {
    public let environment: EngineEnvironment
    public init(environment: EngineEnvironment) { self.environment = environment }
    public func run(input: URL, pipeline: PinnedPipeline, outputDirectory: URL? = nil,
                    cancellation: CancellationToken = CancellationToken()) throws -> ConversionResult {
        try cancellation.check()
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard input.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true,
              let bytes = values.fileSize, bytes > 0, bytes <= 1_073_741_824, FileKind.detect(input) == .image else {
            throw ConversionError.unsupported("This pinned pipeline accepts one regular image up to 1 GB. Other files can be pinned to Quick Stash.")
        }
        let directory = outputDirectory ?? input.deletingLastPathComponent()
        let workspace = directory.appendingPathComponent(".fileorbit-pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let snapshot = workspace.appendingPathComponent("source." + input.pathExtension)
        try FileManager.default.copyItem(at: input, to: snapshot)
        let engine = ConversionEngine(environment: environment)
        var current = snapshot
        if pipeline == .compress || pipeline == .optimizeWebP {
            do { current = try engine.run(ConversionRequest(input: current, operation: .compress(.balanced), outputDirectory: workspace), cancellation: cancellation).outputURLs[0] }
            catch ConversionError.notSmaller { if pipeline == .compress { throw ConversionError.notSmaller } }
            catch ConversionError.unsupported { if pipeline == .compress { throw ConversionError.unsupported("This image cannot be compressed in place. Try PNG or WebP.") } }
        }
        try cancellation.check()
        if pipeline == .optimizeWebP || pipeline == .png {
            current = try engine.run(ConversionRequest(input: current, operation: .convert(pipeline == .png ? .png : .webp), outputDirectory: workspace), cancellation: cancellation).outputURLs[0]
        }
        let count = try current.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard current != snapshot, count > 0 else { throw ConversionError.failed("The pipeline did not produce a complete result.") }
        try cancellation.check()
        let published = try OutputPublisher.publish(files: [current], source: input, directory: directory, compressed: pipeline == .compress)
        return ConversionResult(outputURLs: published, inputBytes: Int64(bytes), outputBytes: Int64(count), note: "Completed locally: \(pipeline.title). Your original is unchanged.")
    }
}
