import AppKit
import Foundation
import SwiftData
import XCTest
@testable import MenuBarClipboard

@MainActor
final class ClipPickerViewModelTests: XCTestCase {
    private final class SpyPaster: ClipPasting {
        private(set) var pasted: [ClipEntry] = []

        func paste(_ entry: ClipEntry) {
            pasted.append(entry)
        }
    }

    func testFiltersEntriesByPreviewCaseInsensitively() throws {
        let (viewModel, _, _) = try makeViewModel(previews: ["Alpha", "beta", "Gamma"])
        viewModel.reload()

        viewModel.searchText = "A"
        XCTAssertEqual(viewModel.filteredEntries.map(\.preview), ["Gamma", "beta", "Alpha"])

        viewModel.searchText = "bet"
        XCTAssertEqual(viewModel.filteredEntries.map(\.preview), ["beta"])

        viewModel.searchText = "  "
        XCTAssertEqual(viewModel.filteredEntries.count, 3)
    }

    func testSelectionMovesAndClampsAtBounds() throws {
        let (viewModel, _, _) = try makeViewModel(previews: ["one", "two", "three"])
        viewModel.reload()

        viewModel.handle(.moveSelection(-1))
        XCTAssertEqual(viewModel.selectedIndex, 0)

        viewModel.handle(.moveSelection(1))
        viewModel.handle(.moveSelection(1))
        viewModel.handle(.moveSelection(1))
        XCTAssertEqual(viewModel.selectedIndex, 2)
        XCTAssertEqual(viewModel.selectedEntry?.preview, "one")
    }

    func testSelectionClampsWhenSearchShrinksResults() throws {
        let (viewModel, _, _) = try makeViewModel(previews: ["alpha", "beta", "gamma"])
        viewModel.reload()
        viewModel.selectedIndex = 2

        viewModel.searchText = "alpha"
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedEntry?.preview, "alpha")
    }

    func testPasteSendsSelectedEntryAndDismisses() throws {
        let (viewModel, _, paster) = try makeViewModel(previews: ["alpha", "beta"])
        viewModel.reload()
        var dismissed = false
        viewModel.onDismiss = { dismissed = true }

        viewModel.handle(.moveSelection(1))
        viewModel.handle(.pasteSelection)

        XCTAssertEqual(paster.pasted.map(\.preview), ["alpha"])
        XCTAssertTrue(dismissed)
    }

    func testDeleteRemovesSelectedEntryFromStore() throws {
        let (viewModel, store, _) = try makeViewModel(previews: ["alpha", "beta"])
        viewModel.reload()

        viewModel.handle(.deleteSelection)

        XCTAssertEqual(try store.entries().map(\.preview), ["alpha"])
        XCTAssertEqual(viewModel.filteredEntries.map(\.preview), ["alpha"])
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testDeleteOnEmptyListIsNoOp() throws {
        let (viewModel, _, _) = try makeViewModel(previews: [])
        viewModel.reload()

        viewModel.handle(.deleteSelection)

        XCTAssertNil(viewModel.selectedEntry)
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testTogglePinMovesEntryToPinnedGroupAndPreservesSelection() throws {
        let (viewModel, _, _) = try makeViewModel(previews: ["old", "new"])
        viewModel.reload()
        viewModel.selectedIndex = 1
        let selectedID = try XCTUnwrap(viewModel.selectedEntry?.id)

        viewModel.togglePin(try XCTUnwrap(viewModel.selectedEntry))

        XCTAssertTrue(viewModel.entries.first?.pinned == true)
        XCTAssertEqual(viewModel.selectedEntry?.id, selectedID)
    }

    func testDeleteAllClearsViewAndStore() throws {
        let (viewModel, store, _) = try makeViewModel(previews: ["one", "two"])
        viewModel.reload()
        var preparedMonitor = false
        viewModel.onDeleteAll = { preparedMonitor = true }

        viewModel.deleteAll()

        XCTAssertTrue(preparedMonitor)
        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertTrue(try store.entries().isEmpty)
    }

    func testPrepareForPresentationResetsTransientState() throws {
        let (viewModel, _, _) = try makeViewModel(previews: ["alpha", "beta"])
        viewModel.reload()
        viewModel.searchText = "beta"
        viewModel.focus = .search
        let previousPresentationID = viewModel.presentationID

        viewModel.prepareForPresentation()

        XCTAssertNotEqual(viewModel.presentationID, previousPresentationID)
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.focus, .list)
        XCTAssertEqual(viewModel.filteredEntries.count, 2)
    }

    func testFocusSearchCommandMovesFocus() throws {
        let (viewModel, _, _) = try makeViewModel(previews: ["alpha"])
        viewModel.reload()

        viewModel.handle(.focusSearch)

        XCTAssertEqual(viewModel.focus, .search)
    }

    private func makeViewModel(
        previews: [String]
    ) throws -> (ClipPickerViewModel, ClipboardHistoryStore, SpyPaster) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ClipEntry.self,
            configurations: configuration
        )
        let store = ClipboardHistoryStore(modelContainer: container)
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        for (index, preview) in previews.enumerated() {
            _ = try store.capture(
                CapturedClip(
                    kind: .text,
                    preview: preview,
                    data: Data(preview.utf8)
                ),
                at: baseDate.addingTimeInterval(TimeInterval(index))
            )
        }
        let paster = SpyPaster()
        return (
            ClipPickerViewModel(historyStore: store, paster: paster),
            store,
            paster
        )
    }
}

final class PickerCommandTests: XCTestCase {
    func testArrowKeysMoveSelection() {
        XCTAssertEqual(
            PickerCommand.from(keyCode: 126, modifiers: [], focus: .list),
            .moveSelection(-1)
        )
        XCTAssertEqual(
            PickerCommand.from(keyCode: 125, modifiers: [], focus: .search),
            .moveSelection(1)
        )
    }

    func testReturnPastesAndEscapeDismisses() {
        XCTAssertEqual(
            PickerCommand.from(keyCode: 36, modifiers: [], focus: .search),
            .pasteSelection
        )
        XCTAssertEqual(
            PickerCommand.from(keyCode: 53, modifiers: [], focus: .search),
            .dismiss
        )
    }

    func testCommandFFocusesSearch() {
        XCTAssertEqual(
            PickerCommand.from(keyCode: 3, modifiers: [.command], focus: .list),
            .focusSearch
        )
        XCTAssertNil(PickerCommand.from(keyCode: 3, modifiers: [], focus: .list))
    }

    func testDeleteEditsSearchTextWhileSearchFieldIsFocused() {
        XCTAssertEqual(
            PickerCommand.from(keyCode: 51, modifiers: [], focus: .list),
            .deleteSelection
        )
        XCTAssertNil(
            PickerCommand.from(keyCode: 51, modifiers: [], focus: .search)
        )
        XCTAssertEqual(
            PickerCommand.from(keyCode: 51, modifiers: [.command], focus: .search),
            .deleteSelection
        )
    }

    func testUnmappedKeyReturnsNil() {
        XCTAssertNil(PickerCommand.from(keyCode: 0, modifiers: [], focus: .list))
    }
}
