import Testing
@testable import FileOrbit

struct FinderDragSessionTests {
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
