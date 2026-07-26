import Carbon
import Foundation

/// The picker's global shortcut, stored as Carbon values because that is what
/// `RegisterEventHotKey` takes and what `HotKey`'s `KeyCombo` exposes.
struct ShortcutPreference: Equatable {
    var carbonKeyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = ShortcutPreference(
        carbonKeyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(cmdKey | optionKey)
    )

    static let defaultsKey = "pickerShortcut"

    /// Global hot keys that carry only Shift, or no modifier at all, would fire
    /// while the user is typing.
    var isValid: Bool {
        let required = UInt32(cmdKey | controlKey | optionKey)
        return carbonModifiers & required != 0
    }

    // MARK: - Persistence

    init(carbonKeyCode: UInt32, carbonModifiers: UInt32) {
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers
    }

    init?(dictionary: [String: Any]) {
        guard let keyCode = dictionary["keyCode"] as? Int,
              let modifiers = dictionary["modifiers"] as? Int
        else {
            return nil
        }
        self.init(
            carbonKeyCode: UInt32(keyCode),
            carbonModifiers: UInt32(modifiers)
        )
    }

    var dictionary: [String: Any] {
        ["keyCode": Int(carbonKeyCode), "modifiers": Int(carbonModifiers)]
    }

    static func load(from defaults: UserDefaults) -> ShortcutPreference {
        guard let stored = defaults.dictionary(forKey: defaultsKey),
              let preference = ShortcutPreference(dictionary: stored),
              preference.isValid
        else {
            return .default
        }
        return preference
    }

    func save(to defaults: UserDefaults) {
        defaults.set(dictionary, forKey: Self.defaultsKey)
    }
}
