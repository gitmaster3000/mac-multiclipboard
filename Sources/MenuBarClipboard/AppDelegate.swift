import AppKit
import HotKey
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var clipboardMonitor: ClipboardMonitor?
    private var pickerController: ClipPickerPanelController?
    private var settingsController: SettingsWindowController?
    private var hotKey: HotKey?
    private var screenshotHotKey: HotKey?
    private var fullScreenshotHotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `open -n` and double-clicking the bundle can otherwise start another
        // menu-bar process. Two copies would both watch the pasteboard and try
        // to register the global shortcut, so keep the already-running copy.
        guard !activateExistingInstanceIfNeeded() else {
            NSApp.terminate(nil)
            return
        }

        // Create the status item first — on macOS 26 the item must be registered
        // before setActivationPolicy or it is silently hidden.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Multiclipboard")
            image?.isTemplate = true
            button.image = image
        }
        item.isVisible = true
        statusItem = item

        NSApp.setActivationPolicy(.accessory)
        AppearancePreference.load(from: .standard).apply()

        do {
            let historyStore = try ClipboardHistoryStore()
            let promptStore = try PromptStore()
            setUpPicker(historyStore: historyStore, promptStore: promptStore)
            let monitor = ClipboardMonitor(
                historyStore: historyStore,
                onHistoryChange: { [weak self] in
                    self?.pickerController?.historyDidChange()
                }
            )
            pickerController?.setDeleteAllHandler { [weak monitor] in
                monitor?.discardPendingPasteboardChange()
            }
            monitor.start()
            clipboardMonitor = monitor
        } catch {
            NSLog("Unable to initialize clipboard history: \(error)")
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: "Show Clipboard History", action: #selector(showPicker), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items where !menuItem.isSeparatorItem {
            menuItem.target = self
            menuItem.isEnabled = true
        }
        statusItem?.menu = menu
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
    }

    /// Activates an existing copy of this app and reports whether launch should
    /// stop. This is deliberately based on the bundle identifier, not the app
    /// path, so it also handles a copy started from a different location.
    private func activateExistingInstanceIfNeeded() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        guard let existingInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentProcessID })
        else {
            return false
        }

        existingInstance.activate()
        return true
    }

    @MainActor
    private func setUpPicker(historyStore: ClipboardHistoryStore, promptStore: PromptStore) {
        let viewModel = ClipPickerViewModel(
            historyStore: historyStore,
            paster: SystemClipPaster()
        )
        let promptViewModel = PromptLibraryViewModel(store: promptStore)
        let controller = ClipPickerPanelController(viewModel: viewModel, promptViewModel: promptViewModel)
        pickerController = controller

        applyShortcut(ShortcutPreference.load(from: .standard))
        applyScreenshotShortcut(
            ScreenshotShortcutPreference.load(from: .standard)
        )
        applyFullScreenshotShortcut(
            FullScreenshotShortcutPreference.load(from: .standard)
        )

        settingsController = SettingsWindowController(
            viewModel: SettingsViewModel(
                apply: { [weak self] shortcut in
                    self?.applyShortcut(shortcut)
                },
                applyScreenshot: { [weak self] shortcut in
                    self?.applyScreenshotShortcut(shortcut)
                },
                applyFullScreenshot: { [weak self] shortcut in
                    self?.applyFullScreenshotShortcut(shortcut)
                }
            )
        )
    }

    /// Registers the picker hot key, replacing any existing one. Passing `nil`
    /// leaves no hot key registered, which the settings probe needs so it can
    /// claim the combo it is testing.
    @MainActor
    private func applyShortcut(_ shortcut: ShortcutPreference?) {
        hotKey = nil

        guard let shortcut, shortcut.isValid else { return }

        let hotKey = HotKey(
            keyCombo: KeyCombo(
                carbonKeyCode: shortcut.carbonKeyCode,
                carbonModifiers: shortcut.carbonModifiers
            )
        )
        hotKey.keyDownHandler = { [weak self] in
            MainActor.assumeIsolated {
                self?.pickerController?.toggle()
            }
        }
        self.hotKey = hotKey
    }

    @MainActor
    private func applyScreenshotShortcut(_ shortcut: ShortcutPreference?) {
        screenshotHotKey = nil
        guard let shortcut, shortcut.isValid else { return }

        let hotKey = HotKey(
            keyCombo: KeyCombo(
                carbonKeyCode: shortcut.carbonKeyCode,
                carbonModifiers: shortcut.carbonModifiers
            )
        )
        hotKey.keyDownHandler = { [weak self] in
            MainActor.assumeIsolated {
                self?.captureScreenshotToClipboard()
            }
        }
        screenshotHotKey = hotKey
    }

    @MainActor
    private func applyFullScreenshotShortcut(
        _ shortcut: ShortcutPreference?
    ) {
        fullScreenshotHotKey = nil
        guard let shortcut, shortcut.isValid else { return }

        let hotKey = HotKey(
            keyCombo: KeyCombo(
                carbonKeyCode: shortcut.carbonKeyCode,
                carbonModifiers: shortcut.carbonModifiers
            )
        )
        hotKey.keyDownHandler = { [weak self] in
            MainActor.assumeIsolated {
                self?.captureScreenshotToClipboard(interactive: false)
            }
        }
        fullScreenshotHotKey = hotKey
    }

    @MainActor
    private func captureScreenshotToClipboard(interactive: Bool = true) {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = interactive ? ["-i", "-c"] : ["-c"]
        task.standardError = pipe
        task.terminationHandler = { [weak self] t in
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                if t.terminationStatus != 0 && output.contains("could not create image from display") {
                    self?.showScreenRecordingPermissionAlert()
                } else if t.terminationStatus == 0 {
                    self?.clipboardMonitor?.poll()
                    self?.showScreenshotSuccessBanner()
                }
            }
        }

        do {
            try task.run()
        } catch {
            NSLog("Unable to launch macOS screenshot capture: \(error)")
        }
    }

    private var toastPanel: NSPanel?

    @MainActor
    private func showScreenshotSuccessBanner() {
        // A self-drawn floating toast. UNUserNotificationCenter is unreliable for
        // an unsigned .accessory app, so we render our own HUD instead.
        toastPanel?.orderOut(nil)

        let width: CGFloat = 260
        let height: CGFloat = 60
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: ScreenshotToastView())
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        panel.contentView = host

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.midX - width / 2
            let y = visible.maxY - height - 24
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        toastPanel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            guard let panel = self?.toastPanel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.45
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
                if self?.toastPanel === panel { self?.toastPanel = nil }
            }
        }
    }

    @MainActor
    private func showScreenRecordingPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Multiclipboard needs Screen Recording access to capture screenshots.\n\nEnable it in System Settings → Privacy & Security → Screen & System Audio Recording."
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    @objc private func showPicker() {
        pickerController?.show()
    }

    @MainActor
    @objc private func showSettings() {
        settingsController?.show()
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString(string: "Created by Ali Faraz\n")
        let website = NSAttributedString(
            string: "alifaraz.de",
            attributes: [
                .link: URL(string: "https://alifaraz.de") as Any,
                .foregroundColor: NSColor.linkColor
            ]
        )
        credits.append(website)

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Multiclipboard",
            .applicationVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "1.4.1",
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private struct ScreenshotToastView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Screenshot captured")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Added to clipboard history")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}
