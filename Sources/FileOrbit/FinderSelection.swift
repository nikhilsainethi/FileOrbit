import AppKit

@MainActor
enum FinderSelection {
    static func selectedFile() throws -> URL {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            throw SelectionError.message("Select a file in Finder, then double-tap Command.")
        }
        // Constant script: no filenames or user content interpolated into AppleScript.
        let source = """
        tell application id "com.apple.finder"
            set chosenItems to selection as alias list
            if (count of chosenItems) is not 1 then return ""
            return POSIX path of (item 1 of chosenItems)
        end tell
        """
        guard let script = NSAppleScript(source: source) else { throw SelectionError.message("Could not read the Finder selection.") }
        var details: NSDictionary?
        let value = script.executeAndReturnError(&details)
        if let details {
            if (details[NSAppleScript.errorNumber] as? Int) == -1743 {
                throw SelectionError.message("Allow FileOrbit to control Finder in System Settings → Privacy & Security → Automation, then try again. You can also use Choose file.")
            }
            throw SelectionError.message("Finder could not provide the selected file. Try selecting it again or use Choose file.")
        }
        guard let path = value.stringValue, !path.isEmpty else { throw SelectionError.message("Select exactly one file in Finder, then double-tap Command. Batch conversion is not included in this version.") }
        return URL(fileURLWithPath: path)
    }
    enum SelectionError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
    }
}
