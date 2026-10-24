import Foundation
import PDFKit

public enum OfficeConverter {
    public static func convert(input: URL, to format: OutputFormat, workspace: URL,
                               environment: EngineEnvironment, cancellation: CancellationToken) throws -> [URL] {
        try cancellation.check()
        guard let executable = environment.libreOfficeURL, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ConversionError.missingDependency("Install LibreOffice locally, then set its application path in FileOrbit Settings.")
        }
        let ext = input.pathExtension.lowercased()
        let allowed: [String: Set<OutputFormat>] = ["docx": [.pdf, .txt], "pptx": [.pdf, .png, .jpg], "txt": [.pdf, .docx]]
        guard allowed[ext]?.contains(format) == true else { throw ConversionError.unsupported("This Office conversion is not supported.") }
        let inputValues = try input.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        let maximumBytes = (ext == "txt" ? 32 : 256) * 1024 * 1024
        guard inputValues.isRegularFile == true, let inputBytes = inputValues.fileSize, inputBytes > 0, inputBytes <= maximumBytes else {
            throw ConversionError.unsupported("Select a nonempty \(ext.uppercased()) file smaller than \(maximumBytes / 1024 / 1024) MB.")
        }
        let job = workspace.appendingPathComponent("office-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: job) }
        let source = job.appendingPathComponent("source.\(ext)")
        try FileManager.default.copyItem(at: input, to: source)
        if ext == "docx" || ext == "pptx" {
            let inspected = job.appendingPathComponent("inspection", isDirectory: true)
            try OfficePackage.unpack(input: source, into: inspected, cancellation: cancellation, rejectActiveContent: true)
            let mainPart = ext == "docx" ? "word/document.xml" : "ppt/presentation.xml"
            guard FileManager.default.fileExists(atPath: inspected.appendingPathComponent(mainPart).path) else {
                throw ConversionError.invalidInput("The Office file does not contain the expected document part.")
            }
            try FileManager.default.removeItem(at: inspected)
        } else {
            let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0, bytes <= 32 * 1024 * 1024 else { throw ConversionError.unsupported("Text files must be nonempty and smaller than 32 MB.") }
            guard String(data: try Data(contentsOf: source), encoding: .utf8) != nil else { throw ConversionError.unsupported("Save this text file with UTF-8 encoding before converting it.") }
        }
        let profile = job.appendingPathComponent("profile", isDirectory: true)
        let user = profile.appendingPathComponent("user", isDirectory: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        // A separate user profile prevents attaching to a running LibreOffice and disables macro/link execution.
        let config = """
        <?xml version="1.0" encoding="UTF-8"?>
        <oor:items xmlns:oor="http://openoffice.org/2001/registry">
          <item oor:path="/org.openoffice.Office.Common/Security/Scripting"><prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop><prop oor:name="DisableMacrosExecution" oor:op="fuse"><value>true</value></prop></item>
          <item oor:path="/org.openoffice.Office.Writer/Content/Update"><prop oor:name="Link" oor:op="fuse"><value>2</value></prop></item>
        </oor:items>
        """
        try config.write(to: user.appendingPathComponent("registrymodifications.xcu"), atomically: true, encoding: .utf8)
        let exportDirectory = job.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let intermediateFormat: OutputFormat = (format == .png || format == .jpg) ? .pdf : format
        let filter: String
        switch intermediateFormat {
        case .pdf: filter = ext == "pptx" ? "pdf:impress_pdf_Export" : "pdf:writer_pdf_Export"
        case .txt: filter = "txt:Text (encoded):UTF8"
        case .docx: filter = "docx:Office Open XML Text"
        default: throw ConversionError.unsupported("This Office export format is not supported.")
        }
        var arguments = ["-env:UserInstallation=\(profile.absoluteString)", "--headless", "--nologo", "--nodefault", "--norestore", "--nofirststartwizard"]
        if ext == "txt" { arguments += ["--infilter=Text (encoded):UTF8,LF"] }
        arguments += ["--convert-to", filter, "--outdir", exportDirectory.path, source.path]
        _ = try LocalProcess.run(executable: executable, arguments: arguments, timeout: 120, cancellation: cancellation, directory: job)
        try cancellation.check()
        let exported = exportDirectory.appendingPathComponent("source.\(intermediateFormat.rawValue)")
        guard FileManager.default.fileExists(atPath: exported.path), (try exported.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 > 0 else {
            throw ConversionError.failed("LibreOffice did not produce a valid output. The file may be damaged, protected, or unsupported.")
        }
        switch intermediateFormat {
        case .pdf:
            guard let pdf = PDFDocument(url: exported), !pdf.isLocked, pdf.pageCount > 0 else { throw ConversionError.failed("LibreOffice produced an unreadable PDF.") }
        case .docx: try OfficePackage.validateArchive(exported)
        case .txt:
            guard String(data: try Data(contentsOf: exported), encoding: .utf8) != nil else { throw ConversionError.failed("LibreOffice did not produce UTF-8 text.") }
        default: break
        }
        if format == .png || format == .jpg {
            return try NativeConverter.convertPDF(input: exported, to: format, workspace: workspace, cancellation: cancellation)
        }
        let output = workspace.appendingPathComponent("converted.\(format.rawValue)")
        guard !FileManager.default.fileExists(atPath: output.path) else { throw ConversionError.failed("Temporary output already exists.") }
        try FileManager.default.moveItem(at: exported, to: output)
        return [output]
    }
}
