import AppKit
import Foundation

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let defaultsKey = "appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let preference = Self(rawValue: rawValue)
        else {
            return .system
        }
        return preference
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    @MainActor
    func apply() {
        switch self {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
