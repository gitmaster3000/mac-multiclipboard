import Carbon
import XCTest
@testable import MenuBarClipboard

final class ShortcutPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ShortcutPreferenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRoundTripsThroughUserDefaults() {
        let shortcut = ShortcutPreference(
            carbonKeyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(cmdKey | controlKey)
        )

        shortcut.save(to: defaults)

        XCTAssertEqual(ShortcutPreference.load(from: defaults), shortcut)
    }

    func testFallsBackToDefaultWhenNothingStored() {
        XCTAssertEqual(ShortcutPreference.load(from: defaults), .default)
    }

    func testFallsBackToDefaultWhenStoredValueIsMalformed() {
        defaults.set(["unexpected": "shape"], forKey: ShortcutPreference.defaultsKey)

        XCTAssertEqual(ShortcutPreference.load(from: defaults), .default)
    }

    func testFallsBackToDefaultWhenStoredValueIsInvalid() {
        // Shift-only sneaked into defaults by hand or by an older build.
        let invalid = ShortcutPreference(
            carbonKeyCode: UInt32(kVK_ANSI_V),
            carbonModifiers: UInt32(shiftKey)
        )
        invalid.save(to: defaults)

        XCTAssertEqual(ShortcutPreference.load(from: defaults), .default)
    }

    func testRejectsCombosWithoutCommandControlOrOption() {
        let noModifier = ShortcutPreference(
            carbonKeyCode: UInt32(kVK_ANSI_V),
            carbonModifiers: 0
        )
        let shiftOnly = ShortcutPreference(
            carbonKeyCode: UInt32(kVK_ANSI_V),
            carbonModifiers: UInt32(shiftKey)
        )

        XCTAssertFalse(noModifier.isValid)
        XCTAssertFalse(shiftOnly.isValid)
    }

    func testAcceptsCombosWithAtLeastOneRequiredModifier() {
        let combos = [
            UInt32(cmdKey),
            UInt32(controlKey),
            UInt32(optionKey),
            UInt32(cmdKey | shiftKey),
        ]

        for modifiers in combos {
            let shortcut = ShortcutPreference(
                carbonKeyCode: UInt32(kVK_ANSI_V),
                carbonModifiers: modifiers
            )
            XCTAssertTrue(shortcut.isValid, "expected \(modifiers) to be valid")
        }
    }

    func testDefaultIsCommandOptionV() {
        XCTAssertEqual(ShortcutPreference.default.carbonKeyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(
            ShortcutPreference.default.carbonModifiers,
            UInt32(cmdKey | optionKey)
        )
        XCTAssertTrue(ShortcutPreference.default.isValid)
    }

    func testScreenshotShortcutDefaultsAndRoundTrips() {
        XCTAssertEqual(
            ScreenshotShortcutPreference.default.carbonKeyCode,
            UInt32(kVK_ANSI_S)
        )
        XCTAssertEqual(
            ScreenshotShortcutPreference.default.carbonModifiers,
            UInt32(optionKey | shiftKey)
        )

        let custom = ShortcutPreference(
            carbonKeyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(controlKey | shiftKey)
        )
        ScreenshotShortcutPreference.save(custom, to: defaults)

        XCTAssertEqual(
            ScreenshotShortcutPreference.load(from: defaults),
            custom
        )

        XCTAssertEqual(
            FullScreenshotShortcutPreference.default.carbonKeyCode,
            UInt32(kVK_ANSI_3)
        )
        XCTAssertEqual(
            FullScreenshotShortcutPreference.default.carbonModifiers,
            UInt32(optionKey | shiftKey)
        )

        FullScreenshotShortcutPreference.save(custom, to: defaults)
        XCTAssertEqual(
            FullScreenshotShortcutPreference.load(from: defaults),
            custom
        )
    }

    func testDisplayStringOrdersModifiersLikeMacOS() {
        let shortcut = ShortcutPreference(
            carbonKeyCode: UInt32(kVK_ANSI_V),
            carbonModifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey)
        )

        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧⌘V")
    }

    func testDisplayStringNamesNonPrintableKeys() {
        let shortcut = ShortcutPreference(
            carbonKeyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(cmdKey)
        )

        XCTAssertEqual(shortcut.displayString, "⌘Space")
    }
}
