import AppKit
import Carbon
import SwiftUI

/// Click-then-press field for capturing a shortcut.
///
/// Wraps an `NSView` rather than using SwiftUI key handling because it needs
/// raw `keyCode` values (layout independent) and must swallow the key event so
/// the combo does not also reach the app.
struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onRecord: (ShortcutPreference) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = onRecord
        view.onRecordingChange = { isRecording = $0 }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onRecord = onRecord
        if isRecording, view.window?.firstResponder !== view {
            view.window?.makeFirstResponder(view)
        }
    }

    final class RecorderView: NSView {
        var onRecord: ((ShortcutPreference) -> Void)?
        var onRecordingChange: ((Bool) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func becomeFirstResponder() -> Bool {
            onRecordingChange?(true)
            return super.becomeFirstResponder()
        }

        override func resignFirstResponder() -> Bool {
            onRecordingChange?(false)
            return super.resignFirstResponder()
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == UInt16(kVK_Escape) {
                window?.makeFirstResponder(nil)
                return
            }

            let shortcut = ShortcutPreference(
                carbonKeyCode: UInt32(event.keyCode),
                carbonModifiers: event.modifierFlags.carbonModifiers
            )

            // Ignore combos that would fire while typing; keep listening so the
            // user can try again without re-clicking the field.
            guard shortcut.isValid else { return }

            window?.makeFirstResponder(nil)
            onRecord?(shortcut)
        }

        /// Swallow modifier-only presses so they do not beep.
        override func flagsChanged(with event: NSEvent) {}

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // While recording, the field owns every combo, including ones that
            // would otherwise be menu shortcuts such as Cmd+Q.
            guard window?.firstResponder === self else { return false }
            keyDown(with: event)
            return true
        }
    }
}

extension NSEvent.ModifierFlags {
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if contains(.command) { result |= UInt32(cmdKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.control) { result |= UInt32(controlKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
