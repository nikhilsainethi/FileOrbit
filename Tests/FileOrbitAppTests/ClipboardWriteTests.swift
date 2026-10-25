import Testing
import AppKit
@testable import FileOrbit
@MainActor struct ClipboardWriteTests {
    @Test func newerClipboardIsNotClaimedAsCopied() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("old", forType: .string); let revision = board.changeCount
        board.clearContents(); board.setString("newer", forType: .string)
        let result = FileOrbitClipboard.write(Data("replacement".utf8), type: .string, expectedRevision: revision, pasteboard: board)
        #expect(result == .changed)
        #expect(board.string(forType: .string) == "newer")
        #expect(FileOrbitClipboard.write(Data("explicit".utf8), type: .string, expectedRevision: board.changeCount, pasteboard: board) == .written)
        #expect(board.string(forType: .string) == "explicit")
        #expect(board.string(forType: FileOrbitClipboard.marker) == "FileOrbit")
    }
}
