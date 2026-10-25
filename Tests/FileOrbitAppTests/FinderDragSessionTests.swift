import Testing
import AppKit
@testable import FileOrbit

@MainActor struct FinderDragSessionTests {
    @Test func mouseDragNeverReadsKeyboardOnlyProperties() throws {
        let mouse = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        #expect(FinderDragKey.spaceState(for: mouse) == nil)
        let down = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        let up = try #require(NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: 2, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        #expect(FinderDragKey.spaceState(for: down) == true)
        #expect(FinderDragKey.spaceState(for: up) == false)
    }
    @Test func previousDragCannotBeReusedByShiftSelection() {
        var session = FinderDragSession()
        session.mouseDown(pasteboardChange: 12)
        let observed1 = session.observeDrag(pasteboardChange: 12)
        #expect(!observed1)
        #expect(!session.isCurrent(pasteboardChange: 12))
        let observed2 = session.observeDrag(pasteboardChange: 13)
        #expect(observed2)
        #expect(session.isCurrent(pasteboardChange: 13))
        session.end()
        session.mouseDown(pasteboardChange: 13)
        let observed3 = session.observeDrag(pasteboardChange: 13)
        #expect(!observed3)
        #expect(!session.isCurrent(pasteboardChange: 13))
    }
    @Test func modifiersCannotStartAFileDragWithoutMouseDownAndNewDrag() {
        var session = FinderDragSession()
        let observed4 = session.observeDrag(pasteboardChange: 9)
        #expect(!observed4)
        session.mouseDown(pasteboardChange: 9)
        #expect(!session.isCurrent(pasteboardChange: 10))
        let observed5 = session.observeDrag(pasteboardChange: 10)
        #expect(observed5)
        session.end()
        #expect(!session.isCurrent(pasteboardChange: 10))
    }
}
