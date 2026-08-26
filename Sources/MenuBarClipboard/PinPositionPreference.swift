import Foundation

enum PinPositionPreference: String, CaseIterable, Identifiable {
    case top
    case bottom

    static let defaultsKey = "pinPosition"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let preference = Self(rawValue: rawValue)
        else {
            return .top
        }
        return preference
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
