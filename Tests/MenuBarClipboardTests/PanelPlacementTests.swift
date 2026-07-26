import XCTest
@testable import MenuBarClipboard

final class PanelPlacementTests: XCTestCase {
    // Bottom-left origin, matching NSScreen.visibleFrame.
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let panel = CGSize(width: 340, height: 420)

    private func origin(cursorX: CGFloat, cursorY: CGFloat) -> CGPoint {
        PanelPlacement.origin(
            cursor: CGPoint(x: cursorX, y: cursorY),
            panelSize: panel,
            visibleFrame: screen
        )
    }

    func testPlacesPanelBelowRightOfCursorWhenThereIsRoom() {
        let result = origin(cursorX: 500, cursorY: 700)

        XCTAssertEqual(result.x, 500 + PanelPlacement.cursorGap)
        XCTAssertEqual(result.y, 700 - PanelPlacement.cursorGap - panel.height)
    }

    func testFlipsToLeftOfCursorNearRightEdge() {
        let result = origin(cursorX: 1400, cursorY: 700)

        XCTAssertEqual(result.x, 1400 - PanelPlacement.cursorGap - panel.width)
        XCTAssertLessThanOrEqual(result.x + panel.width, screen.maxX)
    }

    func testFlipsAboveCursorNearBottomEdge() {
        let result = origin(cursorX: 500, cursorY: 40)

        XCTAssertEqual(result.y, 40 + PanelPlacement.cursorGap)
        XCTAssertGreaterThanOrEqual(result.y, screen.minY)
    }

    func testStaysInsideFrameInBottomRightCorner() {
        let result = origin(cursorX: 1435, cursorY: 10)

        XCTAssertGreaterThanOrEqual(result.x, screen.minX)
        XCTAssertGreaterThanOrEqual(result.y, screen.minY)
        XCTAssertLessThanOrEqual(result.x + panel.width, screen.maxX)
        XCTAssertLessThanOrEqual(result.y + panel.height, screen.maxY)
    }

    func testStaysInsideFrameInTopLeftCorner() {
        let result = origin(cursorX: 2, cursorY: 898)

        XCTAssertGreaterThanOrEqual(result.x, screen.minX)
        XCTAssertLessThanOrEqual(result.y + panel.height, screen.maxY)
    }

    func testRespectsNonZeroFrameOrigin() {
        // Second display sitting to the right of the primary one.
        let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

        let result = PanelPlacement.origin(
            cursor: CGPoint(x: 3400, y: 60),
            panelSize: panel,
            visibleFrame: external
        )

        XCTAssertGreaterThanOrEqual(result.x, external.minX)
        XCTAssertGreaterThanOrEqual(result.y, external.minY)
        XCTAssertLessThanOrEqual(result.x + panel.width, external.maxX)
    }

    func testClampsToTopLeftWhenPanelIsLargerThanFrame() {
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 200)

        let result = PanelPlacement.origin(
            cursor: CGPoint(x: 100, y: 100),
            panelSize: panel,
            visibleFrame: tiny
        )

        XCTAssertEqual(result.x, tiny.minX)
        XCTAssertEqual(result.y, tiny.minY)
    }
}
