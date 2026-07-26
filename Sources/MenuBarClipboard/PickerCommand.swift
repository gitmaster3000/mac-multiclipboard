import AppKit

/// Focus target inside the picker panel. Keyboard routing depends on it:
/// text-editing keys belong to the search field only while it holds focus.
enum PickerFocus {
    case list
    case search
}

enum PickerCommand: Equatable {
    case moveSelection(Int)
    case pasteSelection
    case deleteSelection
    case focusSearch
    case dismiss

    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let f: UInt16 = 3
        static let upArrow: UInt16 = 126
        static let downArrow: UInt16 = 125
    }

    static func from(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        focus: PickerFocus
    ) -> PickerCommand? {
        let command = modifiers.contains(.command)

        switch keyCode {
        case KeyCode.upArrow where !command:
            return .moveSelection(-1)
        case KeyCode.downArrow where !command:
            return .moveSelection(1)
        case KeyCode.returnKey, KeyCode.keypadEnter:
            return .pasteSelection
        case KeyCode.escape:
            return .dismiss
        case KeyCode.f where command:
            return .focusSearch
        case KeyCode.delete where focus == .list || command:
            return .deleteSelection
        default:
            return nil
        }
    }
}
