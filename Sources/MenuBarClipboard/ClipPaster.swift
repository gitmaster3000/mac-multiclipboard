import AppKit

@MainActor
protocol ClipPasting {
    /// Puts the entry back on the pasteboard and asks the frontmost app to paste it.
    func paste(_ entry: ClipEntry)
}

@MainActor
struct SystemClipPaster: ClipPasting {
    private let pasteboard: NSPasteboard
    private static var isShowingAccessibilityHelp = false

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// How frequently to check that the picker has returned focus to another
    /// application before posting the synthetic ⌘V.
    static let focusPollInterval: TimeInterval = 0.05
    static let maximumFocusPolls = 20

    func paste(_ entry: ClipEntry) {
        write(entry)

        // Without Accessibility the synthetic keystroke is dropped with no
        // error, so the clip silently fails to land. Ask for the permission
        // instead of leaving the user to guess.
        guard Self.ensureAccessibility() else { return }

        Self.postPasteWhenTargetIsReady()
    }

    /// Returns whether the app may post events, prompting for the permission
    /// the first time it may not.
    @discardableResult
    static func ensureAccessibility() -> Bool {
        if CGPreflightPostEventAccess() { return true }

        // This registers the app with macOS and presents the system permission
        // request when the OS still permits one. A prior denial or stale TCC
        // entry can make it return false without showing useful guidance, so
        // provide an in-app recovery path as well.
        if CGRequestPostEventAccess() { return true }
        showAccessibilityHelp()
        return false
    }

    private static func showAccessibilityHelp() {
        guard !isShowingAccessibilityHelp else { return }
        isShowingAccessibilityHelp = true

        DispatchQueue.main.async {
            defer { isShowingAccessibilityHelp = false }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
            The selected clip was copied, but Multiclipboard cannot press ⌘V \
            until Accessibility access is enabled.

            Enable Multiclipboard in Privacy & Security → Accessibility. If it \
            is already enabled, turn it off and back on, then reopen the app.
            """
            alert.addButton(withTitle: "Open Accessibility Settings")
            alert.addButton(withTitle: "Not Now")

            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let settingsURL = URL(
                   string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
               ) {
                NSWorkspace.shared.open(settingsURL)
            }
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
            pasteboard.setData(
                entry.data,
                forType: PasteboardExtractor.imagePasteboardType(for: entry.data)
            )
        case .fileURL:
            let urls = String(decoding: entry.data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .compactMap { URL(string: String($0)) }
            pasteboard.writeObjects(urls as [NSURL])
        case nil:
            pasteboard.setString(entry.preview, forType: .string)
        }

        // The clipboard monitor must not recapture a clip that this app just
        // restored for paste-back. Other apps replace this private marker the
        // next time the user copies something normally.
        pasteboard.setString(
            entry.id.uuidString,
            forType: PasteboardExtractor.restoredByMulticlipboardType
        )
    }

    /// Synthesizes ⌘V. Requires the Accessibility permission; without it the
    /// events are silently dropped and the clip is still on the pasteboard.
    private static func postPasteWhenTargetIsReady(poll: Int = 0) {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let frontmostProcessID = NSWorkspace.shared.frontmostApplication?
            .processIdentifier

        if frontmostProcessID != currentProcessID {
            postPasteKeystroke()
            return
        }

        guard poll < maximumFocusPolls else {
            NSLog("Paste-back stopped because no target application regained focus.")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + focusPollInterval) {
            postPasteWhenTargetIsReady(poll: poll + 1)
        }
    }

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
