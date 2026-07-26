import AppKit

@MainActor
protocol ClipPasting {
    /// Puts the entry back on the pasteboard and asks the frontmost app to paste it.
    func paste(_ entry: ClipEntry)
}

@MainActor
struct SystemClipPaster: ClipPasting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Delay before the synthetic ⌘V, so the app that was frontmost before the
    /// picker opened has time to regain key focus.
    static let pasteDelay: TimeInterval = 0.12

    func paste(_ entry: ClipEntry) {
        write(entry)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) {
            Self.postPasteKeystroke()
        }
    }

    func write(_ entry: ClipEntry) {
        pasteboard.clearContents()

        switch entry.clipKind {
        case .text:
            pasteboard.setString(
                String(decoding: entry.data, as: UTF8.self),
                forType: .string
            )
        case .rtf:
            pasteboard.setData(entry.data, forType: .rtf)
        case .image:
            pasteboard.setData(entry.data, forType: .png)
        case .fileURL:
            let urls = String(decoding: entry.data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .compactMap { URL(string: String($0)) }
            pasteboard.writeObjects(urls as [NSURL])
        case nil:
            pasteboard.setString(entry.preview, forType: .string)
        }
    }

    /// Synthesizes ⌘V. Requires the Accessibility permission; without it the
    /// events are silently dropped and the clip is still on the pasteboard.
    private static func postPasteKeystroke() {
        let vKeyCode: CGKeyCode = 9
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: vKeyCode,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: vKeyCode,
                  keyDown: false
              )
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
