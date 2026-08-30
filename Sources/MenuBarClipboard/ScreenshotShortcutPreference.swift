import Carbon
import Foundation

enum ScreenshotShortcutPreference {
    static let defaultsKey = "screenshotShortcut"

    /// Shorter than macOS's four-key clipboard screenshot shortcut while
    /// retaining modifiers so it cannot fire during normal typing.
    static let `default` = ShortcutPreference(
        carbonKeyCode: UInt32(kVK_ANSI_S),
        carbonModifiers: UInt32(optionKey | shiftKey)
    )

    static func load(from defaults: UserDefaults) -> ShortcutPreference {
        guard let stored = defaults.dictionary(forKey: defaultsKey),
              let preference = ShortcutPreference(dictionary: stored),
              preference.isValid
        else {
            return .default
        }
        return preference
    }

    static func save(
        _ preference: ShortcutPreference,
        to defaults: UserDefaults
    ) {
        defaults.set(preference.dictionary, forKey: defaultsKey)
    }
}

enum FullScreenshotShortcutPreference {
    static let defaultsKey = "fullScreenshotShortcut"

    static let `default` = ShortcutPreference(
        carbonKeyCode: UInt32(kVK_ANSI_3),
        carbonModifiers: UInt32(optionKey | shiftKey)
    )

    static func load(from defaults: UserDefaults) -> ShortcutPreference {
        guard let stored = defaults.dictionary(forKey: defaultsKey),
              let preference = ShortcutPreference(dictionary: stored),
              preference.isValid
        else {
            return .default
        }
        return preference
    }

    static func save(
        _ preference: ShortcutPreference,
        to defaults: UserDefaults
    ) {
        defaults.set(preference.dictionary, forKey: defaultsKey)
    }
}
