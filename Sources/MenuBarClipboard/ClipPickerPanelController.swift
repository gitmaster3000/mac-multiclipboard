import AppKit
import SwiftUI

/// Floating panel that can take key focus while the app stays an accessory.
final class ClipPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Preview panel that shows an image beside the picker without stealing key
/// focus, so the picker does not dismiss while the preview is up.
final class ImagePreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClipPickerPanelController: NSObject, NSWindowDelegate {
    private let viewModel: ClipPickerViewModel
    private let promptViewModel: PromptLibraryViewModel?
    private var panel: ClipPickerPanel?
    private var previewPanel: ImagePreviewPanel?
    private var previousApplication: NSRunningApplication?
    private var keyMonitor: Any?

    init(viewModel: ClipPickerViewModel, promptViewModel: PromptLibraryViewModel? = nil) {
        self.viewModel = viewModel
        self.promptViewModel = promptViewModel
        super.init()
        viewModel.onDismiss = { [weak self] in self?.hide() }
        viewModel.onPreviewImage = { [weak self] data in self?.showPreview(data) }
        viewModel.onHidePreview = { [weak self] in self?.hidePreview() }
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func historyDidChange() {
        viewModel.reload()
    }

    func setDeleteAllHandler(_ handler: @escaping () -> Void) {
        viewModel.onDeleteAll = handler
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
        hidePreview()
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        previousApplication?.activate()
        previousApplication = nil
    }

    // MARK: - Image preview

    /// Shows the image beside the picker in a panel that never takes key focus,
    /// sized to roughly a quarter of the screen while respecting aspect ratio.
    private func showPreview(_ data: Data) {
        guard let image = NSImage(data: data), let panel else { return }

        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let targetArea = (visible.width * visible.height) / 4
        let imgSize = image.size
        let aspect = imgSize.width > 0 ? imgSize.width / max(imgSize.height, 1) : 1
        var height = (targetArea / aspect).squareRoot()
        var width = height * aspect
        width = min(width, visible.width * 0.9)
        height = min(height, visible.height * 0.9)

        let preview = previewPanel ?? makePreviewPanel()
        previewPanel = preview
        preview.setContentSize(NSSize(width: width, height: height))
        preview.contentView = NSHostingView(rootView: ImagePreviewContent(image: image))

        // Place to the right of the picker if it fits, otherwise to the left.
        let pickerFrame = panel.frame
        let gap: CGFloat = 12
        var originX = pickerFrame.maxX + gap
        if originX + width > visible.maxX {
            originX = pickerFrame.minX - gap - width
        }
        originX = max(visible.minX, min(originX, visible.maxX - width))
        let originY = min(max(visible.minY, pickerFrame.midY - height / 2), visible.maxY - height)

        preview.setFrameOrigin(NSPoint(x: originX, y: originY))
        preview.orderFront(nil)
    }

    private func hidePreview() {
        previewPanel?.orderOut(nil)
    }

    private func makePreviewPanel() -> ImagePreviewPanel {
        let preview = ImagePreviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        preview.level = .floating
        preview.hidesOnDeactivate = false
        preview.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        preview.isOpaque = false
        preview.backgroundColor = .clear
        preview.hasShadow = true
        preview.isMovableByWindowBackground = true
        return preview
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
            rootView: ClipPickerView(viewModel: viewModel, promptViewModel: promptViewModel)
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
        // Clicking the preview panel (a non-activating panel in the same app)
        // makes the picker resign key. That must not dismiss everything, so if
        // the pointer is over the preview, keep the picker up and re-key it.
        if let preview = previewPanel, preview.isVisible,
           preview.frame.contains(NSEvent.mouseLocation) {
            panel?.makeKey()
            return
        }
        hide()
    }
}
