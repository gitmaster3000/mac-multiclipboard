import Foundation
import ServiceManagement

/// Keeps the Settings UI in sync with macOS's Login Items registration for
/// this application bundle.
@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var message: String?

    init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        // Reflect the user's action immediately. ServiceManagement may take a
        // moment to publish its new status, and `.requiresApproval` is still a
        // registered login item that should remain visibly checked.
        isEnabled = enabled
        message = nil

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.refresh()
            }
        } catch {
            refresh()
            message = "Could not update Login Items: \(error.localizedDescription)"
        }
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = Self.shouldShowEnabled(for: status)

        switch status {
        case .enabled:
            message = nil
        case .requiresApproval:
            message = "Allow Multiclipboard in System Settings → General → Login Items."
        case .notRegistered, .notFound:
            message = nil
        @unknown default:
            message = "Login Item status is unavailable."
        }
    }

    static func shouldShowEnabled(for status: SMAppService.Status) -> Bool {
        switch status {
        case .enabled, .requiresApproval:
            true
        case .notRegistered, .notFound:
            false
        @unknown default:
            false
        }
    }
}
