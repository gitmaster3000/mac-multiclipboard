import Foundation
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

    private let historyStore: ClipboardHistoryStore
    private let paster: ClipPasting
    private let defaults: UserDefaults

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
        selectedIndex = 0
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
