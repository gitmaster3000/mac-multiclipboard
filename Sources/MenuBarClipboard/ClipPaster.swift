import AppKit
import ImageIO

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

        Self.postPasteWhenReady()
    }

    /// Returns whether the app may post events, prompting for the permission
    /// the first time it may not.
    ///
    /// We deliberately gate on `AXIsProcessTrusted()` — the classic
    /// Accessibility grant shown in Privacy & Security → Accessibility — rather
    /// than `CGPreflightPostEventAccess()`. The CoreGraphics post-event API
    /// checks a separate PostEvent grant whose ad-hoc designated requirement is
    /// cdhash-based; every rebuild invalidates it and toggling the Accessibility
    /// switch never satisfies it, so the app prompts on a loop. The AX grant is
    /// the one the user actually toggles, and holding it is sufficient to post a
    /// synthetic ⌘V via `.cghidEventTap`.
    @discardableResult
    static func ensureAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }

        // Presents the system permission request and registers the app in the
        // Accessibility list. Returns immediately; the user grants asynchronously.
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return true }

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
            // Finder can't accept raw image bytes on ⌘V — it only pastes files.
            // When Finder is frontmost, drop the image to a temp file and put the
            // file URL on the pasteboard so ⌘V materializes an actual image file.
            if Self.frontmostAppIsFinder(),
               let fileURL = Self.writeTemporaryImageFile(entry.data, baseName: entry.displayName) {
                pasteboard.writeObjects([fileURL as NSURL])
            } else {
                pasteboard.setData(
                    entry.data,
                    forType: PasteboardExtractor.imagePasteboardType(for: entry.data)
                )
            }
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

    /// Whether the app that will receive the synthetic ⌘V is Finder. The picker
    /// is a non-activating panel, so the frontmost app is still the target the
    /// user was in when they opened the picker.
    private static func frontmostAppIsFinder() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    /// Writes image data to a temp file and returns its URL, so a paste into
    /// Finder produces a real image file rather than dropping nothing. The file
    /// is named after the clip's custom name when present, else a default.
    private static func writeTemporaryImageFile(_ data: Data, baseName: String?) -> URL? {
        let ext: String
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let type = CGImageSourceGetType(source) as? String {
            if type.contains("png") { ext = "png" }
            else if type.contains("jpeg") || type.contains("jpg") { ext = "jpg" }
            else { ext = "png" }
        } else {
            ext = "png"
        }
        let fileName = sanitizedFileName(baseName) ?? "Clipboard image"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName).\(ext)")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Makes a filesystem-safe file name from a user label, or nil if the label
    /// is empty after stripping path-hostile characters.
    private static func sanitizedFileName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(200))
    }

    /// Synthesizes ⌘V. Requires the Accessibility permission; without it the
    /// events are silently dropped and the clip is still on the pasteboard.
    static func postPasteWhenReady(poll: Int = 0) {
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
            postPasteWhenReady(poll: poll + 1)
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
