import Foundation
import ImageIO
import SwiftUI

@MainActor
final class ClipPickerViewModel: ObservableObject {
    @Published private(set) var entries: [ClipEntry] = []
    @Published var searchText: String = "" {
        didSet { clampSelection() }
    }
    @Published var selectedIndex: Int = 0
    @Published var focus: PickerFocus = .list
    @Published private(set) var presentationID = UUID()

    var onDismiss: () -> Void = {}
    var onDeleteAll: () -> Void = {}
    var onPreviewImage: (Data) -> Void = { _ in }
    var onHidePreview: () -> Void = {}

    private let historyStore: ClipboardHistoryStore
    private let paster: ClipPasting
    private let defaults: UserDefaults

    var promptLibraryEnabled: Bool {
        defaults.object(forKey: "promptLibraryEnabled") as? Bool ?? true
    }

    init(
        historyStore: ClipboardHistoryStore,
        paster: ClipPasting,
        defaults: UserDefaults = .standard
    ) {
        self.historyStore = historyStore
        self.paster = paster
        self.defaults = defaults
    }

    var filteredEntries: [ClipEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.preview.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedEntry: ClipEntry? {
        let matches = filteredEntries
        guard matches.indices.contains(selectedIndex) else { return nil }
        return matches[selectedIndex]
    }

    func reload() {
        entries = (
            try? historyStore.entries(
                pinPosition: PinPositionPreference.load(from: defaults)
            )
        ) ?? []
        clampSelection()
    }

    /// Resets transient state so every panel presentation starts fresh.
    func prepareForPresentation() {
        presentationID = UUID()
        searchText = ""
        // -1 leaves no row highlighted until the user navigates with the arrow
        // keys, so the picker does not open with the first row pre-selected.
        selectedIndex = -1
        focus = .list
        reload()
    }

    @discardableResult
    func handle(_ command: PickerCommand) -> Bool {
        switch command {
        case let .moveSelection(offset):
            moveSelection(by: offset)
        case .pasteSelection:
            pasteSelection()
        case .deleteSelection:
            deleteSelection()
        case .focusSearch:
            focus = .search
        case .dismiss:
            onDismiss()
        }
        return true
    }

    func moveSelection(by offset: Int) {
        let count = filteredEntries.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex + offset, 0), count - 1)
    }

    func pasteSelection() {
        guard let entry = selectedEntry else { return }
        onDismiss()
        paster.paste(entry)
    }

    func deleteSelection() {
        guard let entry = selectedEntry else { return }
        delete(entry)
    }

    func delete(_ entry: ClipEntry) {
        try? historyStore.delete(entry)
        reload()
    }

    func deleteAll() {
        onDeleteAll()
        try? historyStore.deleteAll()
        reload()
    }

    func togglePin(_ entry: ClipEntry) {
        let selectedID = selectedEntry?.id
        try? historyStore.setPinned(!entry.pinned, for: entry)
        reload(selecting: selectedID)
    }

    /// Sets or clears a clip's custom name. Empty/whitespace clears it (nil),
    /// so the row falls back to showing the preview. Renaming is a mouse-driven
    /// edit, so it does not move the keyboard-selection highlight onto the row.
    func rename(_ entry: ClipEntry, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed?.isEmpty ?? true) ? nil : trimmed
        try? historyStore.setName(normalized, for: entry)
        reloadClearingSelection()
    }

    /// Replaces the text body of a text/rtf clip. Like rename, this is a
    /// mouse-driven edit and does not leave the row selection-highlighted.
    func editText(_ entry: ClipEntry, to text: String) {
        try? historyStore.setText(text, for: entry)
        reloadClearingSelection()
    }

    func saveImageToDownloads(_ entry: ClipEntry) {
        guard entry.clipKind == .image else { return }
        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        let ext: String
        if let source = CGImageSourceCreateWithData(entry.data as CFData, nil),
           let type = CGImageSourceGetType(source) as? String {
            if type.contains("png") { ext = "png" }
            else if type.contains("jpeg") || type.contains("jpg") { ext = "jpg" }
            else { ext = "png" }
        } else { ext = "png" }
        let fileName = "clipboard-\(Int(entry.createdAt.timeIntervalSince1970)).\(ext)"
        try? entry.data.write(to: dir.appendingPathComponent(fileName))
    }

    /// Reloads entries and clears the selection highlight so no row appears
    /// keyboard-focused. Used after mouse-driven edits (rename, text edit).
    private func reloadClearingSelection() {
        entries = (
            try? historyStore.entries(
                pinPosition: PinPositionPreference.load(from: defaults)
            )
        ) ?? []
        // -1 matches no row, so the blue selection highlight is removed until
        // the next keyboard navigation or click.
        selectedIndex = -1
    }

    private func reload(selecting entryID: UUID?) {
        entries = (
            try? historyStore.entries(
                pinPosition: PinPositionPreference.load(from: defaults)
            )
        ) ?? []
        if let entryID,
           let index = filteredEntries.firstIndex(where: { $0.id == entryID }) {
            selectedIndex = index
        } else {
            clampSelection()
        }
    }

    private func clampSelection() {
        let count = filteredEntries.count
        selectedIndex = count > 0 ? min(selectedIndex, count - 1) : 0
    }
}
