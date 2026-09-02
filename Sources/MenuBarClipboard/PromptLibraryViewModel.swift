import Foundation
import AppKit

@MainActor
final class PromptLibraryViewModel: ObservableObject {
    @Published private(set) var entries: [PromptEntry] = []
    @Published var searchText: String = "" {
        didSet { clampSelection() }
    }
    @Published var selectedIndex: Int = 0
    @Published var presentationID = UUID()

    var onDismiss: () -> Void = {}

    private let store: PromptStore

    init(store: PromptStore) {
        self.store = store
    }

    var filteredEntries: [PromptEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.body.localizedCaseInsensitiveContains(q)
        }
    }

    var selectedEntry: PromptEntry? {
        let list = filteredEntries
        guard list.indices.contains(selectedIndex) else { return nil }
        return list[selectedIndex]
    }

    func reload() {
        entries = (try? store.all()) ?? []
        clampSelection()
    }

    func prepareForPresentation() {
        presentationID = UUID()
        searchText = ""
        selectedIndex = 0
        reload()
    }

    func moveSelection(by offset: Int) {
        let count = filteredEntries.count
        guard count > 0 else { selectedIndex = 0; return }
        selectedIndex = min(max(selectedIndex + offset, 0), count - 1)
    }

    func pasteSelection() {
        guard let entry = selectedEntry else { return }
        onDismiss()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.body, forType: .string)
        pasteboard.setString(UUID().uuidString, forType: PasteboardExtractor.restoredByMulticlipboardType)
        SystemClipPaster.ensureAccessibility()
        SystemClipPaster.postPasteWhenReady()
    }

    func add(title: String, body: String) {
        _ = try? store.add(title: title, body: body)
        reload()
    }

    func update(_ entry: PromptEntry, title: String, body: String) {
        try? store.update(entry, title: title, body: body)
        reload()
    }

    func delete(_ entry: PromptEntry) {
        try? store.delete(entry)
        reload()
    }

    private func clampSelection() {
        let count = filteredEntries.count
        selectedIndex = count > 0 ? min(selectedIndex, count - 1) : 0
    }
}
