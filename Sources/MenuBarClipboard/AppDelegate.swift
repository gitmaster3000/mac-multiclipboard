import AppKit
import HotKey

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var clipboardMonitor: ClipboardMonitor?
    private var pickerController: ClipPickerPanelController?
    private var settingsController: SettingsWindowController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let historyStore = try ClipboardHistoryStore()
            let monitor = ClipboardMonitor(historyStore: historyStore)
            monitor.start()
            clipboardMonitor = monitor
            setUpPicker(historyStore: historyStore)
        } catch {
            NSLog("Unable to initialize clipboard history: \(error)")
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Multiclipboard")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Clipboard History", action: #selector(showPicker), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu

        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
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

        settingsController = SettingsWindowController(
            viewModel: SettingsViewModel { [weak self] shortcut in
                self?.applyShortcut(shortcut)
            }
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
    @objc private func showPicker() {
        pickerController?.show()
    }

    @MainActor
    @objc private func showSettings() {
        settingsController?.show()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
