import Carbon
import Foundation

extension ShortcutPreference {
    /// Glyph form, e.g. "⌘⌥V", for the recorder field and menu item.
    var displayString: String {
        var output = ""
        if carbonModifiers & UInt32(controlKey) != 0 { output += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { output += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { output += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { output += "⌘" }
        output += Self.keyName(for: carbonKeyCode)
        return output
    }

    static func keyName(for carbonKeyCode: UInt32) -> String {
        if let named = namedKeys[Int(carbonKeyCode)] {
            return named
        }
        return character(for: carbonKeyCode) ?? "Key \(carbonKeyCode)"
    }

    private static let namedKeys: [Int: String] = [
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Space: "Space",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Asks the current keyboard layout what this key code types, so the label
    /// matches the user's layout rather than assuming US QWERTY.
    private static func character(for carbonKeyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?
            .takeRetainedValue(),
            let layoutPointer = TISGetInputSourceProperty(
                source,
                kTISPropertyUnicodeKeyLayoutData
            )
        else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer)
            .takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(
                to: UCKeyboardLayout.self
            ) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(carbonKeyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
