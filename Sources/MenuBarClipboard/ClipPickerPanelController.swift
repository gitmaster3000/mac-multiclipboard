import AppKit
import SwiftUI

/// Floating panel that can take key focus while the app stays an accessory.
final class ClipPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ClipPickerPanelController: NSObject, NSWindowDelegate {
    private let viewModel: ClipPickerViewModel
    private var panel: ClipPickerPanel?
    private var previousApplication: NSRunningApplication?
    private var keyMonitor: Any?

    init(viewModel: ClipPickerViewModel) {
        self.viewModel = viewModel
        super.init()
        viewModel.onDismiss = { [weak self] in self?.hide() }
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        previousApplication = NSWorkspace.shared.frontmostApplication
        viewModel.prepareForPresentation()

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        startKeyMonitor()
    }

    func hide() {
        stopKeyMonitor()
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        previousApplication?.activate()
        previousApplication = nil
    }

    private func makePanel() -> ClipPickerPanel {
        let panel = ClipPickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: ClipPickerView(viewModel: viewModel)
        )
        return panel
    }

    /// Intercepts key events before the search field sees them, so navigation
    /// keys keep working while the user is typing a query.
    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.isVisible else { return event }
            guard let command = PickerCommand.from(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                focus: self.viewModel.focus
            ) else { return event }
            self.viewModel.handle(command)
            return nil
        }
    }

    private func stopKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
