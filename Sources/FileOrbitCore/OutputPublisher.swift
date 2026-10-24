import Foundation
import Darwin

/// Atomically publishes complete outputs with an exclusive rename. A racing writer cannot be overwritten.
enum OutputPublisher {
    static func publish(files: [URL], source: URL, directory: URL, compressed: Bool) throws -> [URL] {
        guard !files.isEmpty else { throw ConversionError.failed("The converter did not produce an output.") }
        let stem = safeStem(source.deletingPathExtension().lastPathComponent) + (compressed ? "-compressed" : "-converted")
        if files.count == 1 {
            let ext = files[0].pathExtension
            let destination = try exclusiveMove(from: files[0], to: directory, stem: stem, extension: ext)
            return [destination]
        }
        let payload = files[0].deletingLastPathComponent().appendingPathComponent("publish-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: payload) }
        var names: [String] = []
        for file in files {
            let name = file.lastPathComponent
            guard !names.contains(name) else { throw ConversionError.failed("The converter produced duplicate output names.") }
            names.append(name)
            try FileManager.default.moveItem(at: file, to: payload.appendingPathComponent(name))
        }
        let destination = try exclusiveMove(from: payload, to: directory, stem: stem, extension: "")
        return names.map { destination.appendingPathComponent($0) }
    }

    private static func safeStem(_ value: String) -> String {
        var result = ""
        for character in value {
            guard result.utf8.count + String(character).utf8.count <= 180 else { break }
            result.append(character)
        }
        return result.isEmpty ? "File" : result
    }

    private static func exclusiveMove(from source: URL, to directory: URL, stem: String, extension ext: String) throws -> URL {
        for index in 1...10000 {
            let suffix = index == 1 ? "" : " \(index)"
            let name = stem + suffix + (ext.isEmpty ? "" : ".\(ext)")
            let target = directory.appendingPathComponent(name)
            let result = source.path.withCString { sourcePath in
                target.path.withCString { targetPath in
                    renamex_np(sourcePath, targetPath, UInt32(RENAME_EXCL))
                }
            }
            if result == 0 { return target }
            let code = errno
            if code == EEXIST || code == ENOTEMPTY { continue }
            throw ConversionError.failed("Could not save the output: \(String(cString: strerror(code))). Choose a writable local output folder.")
        }
        throw ConversionError.failed("Too many files already have this output name. Choose another output folder.")
    }
}
