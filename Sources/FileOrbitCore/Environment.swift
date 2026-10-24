import Foundation
public extension EngineEnvironment {
    /// Resolve optional local engines. No engine is downloaded or launched here.
    static func discover(environment: [String: String] = ProcessInfo.processInfo.environment, preferences: [String: String]? = nil, bundleURL: URL = Bundle.main.bundleURL) -> EngineEnvironment {
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        let preferenceKeys = ["FileOrbit.libreOfficePath", "FileOrbit.qpdfPath", "FileOrbit.resvgPath", "FileOrbit.cwebpPath"]
        let preferenceValues = preferences ?? Dictionary(uniqueKeysWithValues: preferenceKeys.compactMap { key in
            UserDefaults.standard.string(forKey: key).map { (key, $0) }
        })
        func executable(_ override: String, preference: String, candidates: [String]) -> URL? {
            let paths = [environment[override], preferenceValues[preference]].compactMap { $0 }
            return (paths + candidates).compactMap { path -> URL? in
                guard path.hasPrefix("/"), !path.isEmpty else { return nil }
                let url = URL(fileURLWithPath: path)
                let resolved = url.resolvingSymlinksInPath()
                guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true,
                      FileManager.default.isExecutableFile(atPath: resolved.path) else { return nil }
                return url
            }.first
        }
        return EngineEnvironment(
            libreOfficeURL: executable("FILEORBIT_SOFFICE", preference: "FileOrbit.libreOfficePath", candidates: [
                "/Applications/LibreOffice.app/Contents/MacOS/soffice",
                userApplications + "/LibreOffice.app/Contents/MacOS/soffice",
                "/opt/homebrew/bin/soffice", "/usr/local/bin/soffice"
            ]),
            qpdfURL: executable("FILEORBIT_QPDF", preference: "FileOrbit.qpdfPath", candidates: [bundleURL.appendingPathComponent("Contents/Helpers/qpdf/bin/qpdf").path, "/opt/homebrew/bin/qpdf", "/usr/local/bin/qpdf"]),
            resvgURL: executable("FILEORBIT_RESVG", preference: "FileOrbit.resvgPath", candidates: [bundleURL.appendingPathComponent("Contents/Helpers/resvg").path, "/opt/homebrew/bin/resvg", "/usr/local/bin/resvg"]),
            cwebpURL: executable("FILEORBIT_CWEBP", preference: "FileOrbit.cwebpPath", candidates: [bundleURL.appendingPathComponent("Contents/Helpers/cwebp").path, "/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"])
        )
    }
}
