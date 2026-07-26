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
        moveToCursor(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        startKeyMonitor()
    }

    /// Opens the panel at the pointer, the way Windows' Win+V does.
    private func moveToCursor(_ panel: ClipPickerPanel) {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        panel.setFrameOrigin(
            PanelPlacement.origin(
                cursor: cursor,
                panelSize: panel.frame.size,
                visibleFrame: visibleFrame
            )
        )
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
            contentRect: NSRect(origin: .zero, size: ClipPickerView.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        // The rounded corners come from the SwiftUI content, so the window
        // itself must not paint a square background behind them.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let hostingView = NSHostingView(
            rootView: ClipPickerView(viewModel: viewModel)
        )
        // Without this the hosting view propagates its intrinsic height to the
        // window, so the panel shrink-wraps to however many clips happen to be
        // in the list instead of keeping a fixed size.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setContentSize(ClipPickerView.panelSize)
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
