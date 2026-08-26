import ServiceManagement
import XCTest
@testable import MenuBarClipboard

@MainActor
final class LaunchAtLoginManagerTests: XCTestCase {
    func testRequiresApprovalStillDisplaysAsEnabled() {
        XCTAssertTrue(
            LaunchAtLoginManager.shouldShowEnabled(for: .requiresApproval)
        )
        XCTAssertTrue(
            LaunchAtLoginManager.shouldShowEnabled(for: .enabled)
        )
        XCTAssertFalse(
            LaunchAtLoginManager.shouldShowEnabled(for: .notRegistered)
        )
        XCTAssertFalse(
            LaunchAtLoginManager.shouldShowEnabled(for: .notFound)
        )
    }
}
