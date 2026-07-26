import Carbon
import XCTest
@testable import MenuBarClipboard

final class ShortcutConfirmationTests: XCTestCase {
    private let shortcut = ShortcutPreference(
        carbonKeyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(cmdKey | optionKey)
    )
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testStartsIdle() {
        XCTAssertEqual(ShortcutConfirmation().state, .idle)
        XCTAssertNil(ShortcutConfirmation().candidate)
    }

    func testMovesToAwaitingOnRecordedCombo() {
        var confirmation = ShortcutConfirmation()
        confirmation.beginAwaiting(shortcut, now: start)

        XCTAssertEqual(
            confirmation.state,
            .awaiting(shortcut, deadline: start.addingTimeInterval(ShortcutConfirmation.timeout))
        )
        XCTAssertEqual(confirmation.candidate, shortcut)
    }

    func testMovesToConfirmedWhenHotKeyFires() {
        var confirmation = ShortcutConfirmation()
        confirmation.beginAwaiting(shortcut, now: start)
        confirmation.recordFire()

        XCTAssertEqual(confirmation.state, .confirmed(shortcut))
    }

    func testMovesToFailedWhenDeadlinePasses() {
        var confirmation = ShortcutConfirmation()
        confirmation.beginAwaiting(shortcut, now: start)
        confirmation.checkDeadline(now: start.addingTimeInterval(ShortcutConfirmation.timeout))

        XCTAssertEqual(confirmation.state, .failed(shortcut))
    }

    func testStaysAwaitingBeforeDeadline() {
        var confirmation = ShortcutConfirmation()
        confirmation.beginAwaiting(shortcut, now: start)
        confirmation.checkDeadline(now: start.addingTimeInterval(ShortcutConfirmation.timeout - 1))

        XCTAssertEqual(
            confirmation.state,
            .awaiting(shortcut, deadline: start.addingTimeInterval(ShortcutConfirmation.timeout))
        )
    }

    func testLateFireDoesNotResurrectFailedState() {
        var confirmation = ShortcutConfirmation()
        confirmation.beginAwaiting(shortcut, now: start)
        confirmation.checkDeadline(now: start.addingTimeInterval(ShortcutConfirmation.timeout))

        confirmation.recordFire()

        XCTAssertEqual(confirmation.state, .failed(shortcut))
    }

    func testFireWhileIdleIsIgnored() {
        var confirmation = ShortcutConfirmation()
        confirmation.recordFire()

        XCTAssertEqual(confirmation.state, .idle)
    }

    func testResetReturnsToIdle() {
        var confirmation = ShortcutConfirmation()
        confirmation.beginAwaiting(shortcut, now: start)
        confirmation.reset()

        XCTAssertEqual(confirmation.state, .idle)
        XCTAssertNil(confirmation.candidate)
    }
}
