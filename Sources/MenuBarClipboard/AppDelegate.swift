import AppKit
import HotKey

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

        NSApp.setActivationPolicy(.accessory)
        AppearancePreference.load(from: .standard).apply()

        do {
            let historyStore = try ClipboardHistoryStore()
            setUpPicker(historyStore: historyStore)
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

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Multiclipboard")
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
        item.menu = menu

        statusItem = item
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
    private func setUpPicker(historyStore: ClipboardHistoryStore) {
        let viewModel = ClipPickerViewModel(
            historyStore: historyStore,
            paster: SystemClipPaster()
        )
        let controller = ClipPickerPanelController(viewModel: viewModel)
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
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = interactive ? ["-i", "-c"] : ["-c"]
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.clipboardMonitor?.poll()
            }
        }

        do {
            try task.run()
        } catch {
            NSLog("Unable to launch macOS screenshot capture: \(error)")
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
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
