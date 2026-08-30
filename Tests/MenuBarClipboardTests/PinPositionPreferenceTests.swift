import Foundation
import XCTest
@testable import MenuBarClipboard

final class PinPositionPreferenceTests: XCTestCase {
    func testDefaultsToTopAndRoundTripsBottom() throws {
        let suiteName = "PinPositionPreferenceTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(PinPositionPreference.load(from: defaults), .top)

        PinPositionPreference.bottom.save(to: defaults)

        XCTAssertEqual(PinPositionPreference.load(from: defaults), .bottom)
    }

    func testAppearanceDefaultsToSystemAndRoundTripsDark() throws {
        let suiteName = "AppearancePreferenceTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppearancePreference.load(from: defaults), .system)

        AppearancePreference.dark.save(to: defaults)

        XCTAssertEqual(AppearancePreference.load(from: defaults), .dark)
    }
}
