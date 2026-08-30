import AppKit
import Foundation
import SwiftData
import XCTest
@testable import MenuBarClipboard

@MainActor
final class ClipboardHistoryStoreTests: XCTestCase {
    func testDeduplicatesByContentHash() throws {
        let store = try makeInMemoryStore()
        let original = CapturedClip(
            kind: .text,
            preview: "Same visible text",
            data: Data("same bytes".utf8)
        )
        let duplicate = CapturedClip(
            kind: .text,
            preview: "Same visible text",
            data: Data("same bytes".utf8)
        )

        XCTAssertNotNil(try store.capture(original))
        XCTAssertNil(try store.capture(duplicate))
        XCTAssertEqual(try store.entries().count, 1)
    }

    func testRecapturingTextMovesExistingEntryToTopWithoutAddingRow() throws {
        let store = try makeInMemoryStore()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try store.capture(
            CapturedClip(
                kind: .text,
                preview: "same text",
                data: Data("same text".utf8)
            ),
            at: baseDate
        )
        _ = try store.capture(clip(1), at: baseDate.addingTimeInterval(1))

        XCTAssertNil(
            try store.capture(
                CapturedClip(
                    kind: .rtf,
                    preview: "same text",
                    data: try NSAttributedString(string: "same text").data(
                        from: NSRange(location: 0, length: 9),
                        documentAttributes: [
                            .documentType: NSAttributedString.DocumentType.rtf
                        ]
                    )
                ),
                at: baseDate.addingTimeInterval(2)
            )
        )

        let entries = try store.entries()
        XCTAssertEqual(entries.map(\.preview), ["same text", "Clip 1"])
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.clipKind, .rtf)
    }

    func testPinnedEntriesSortFirstAndEachGroupIsNewestFirst() throws {
        let store = try makeInMemoryStore()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let oldest = try XCTUnwrap(
            try store.capture(clip(0), at: baseDate)
        )
        _ = try store.capture(clip(1), at: baseDate.addingTimeInterval(1))
        let newest = try XCTUnwrap(
            try store.capture(clip(2), at: baseDate.addingTimeInterval(2))
        )

        try store.setPinned(true, for: oldest)
        try store.setPinned(true, for: newest)

        XCTAssertEqual(
            try store.entries(pinPosition: .top).map(\.preview),
            ["Clip 2", "Clip 0", "Clip 1"]
        )
        XCTAssertEqual(
            try store.entries(pinPosition: .bottom).map(\.preview),
            ["Clip 1", "Clip 2", "Clip 0"]
        )
    }

    func testDifferentLongTextWithSamePreviewRemainsDistinct() throws {
        let store = try makeInMemoryStore()
        let sharedPreview = String(repeating: "a", count: 160)

        _ = try store.capture(
            CapturedClip(
                kind: .text,
                preview: sharedPreview,
                data: Data((sharedPreview + " first").utf8)
            )
        )
        _ = try store.capture(
            CapturedClip(
                kind: .text,
                preview: sharedPreview,
                data: Data((sharedPreview + " second").utf8)
            )
        )

        XCTAssertEqual(try store.entries().count, 2)
    }

    func testDeleteAllRemovesPinnedAndUnpinnedEntries() throws {
        let store = try makeInMemoryStore()
        let pinned = try XCTUnwrap(try store.capture(clip(0)))
        _ = try store.capture(clip(1))
        try store.setPinned(true, for: pinned)

        try store.deleteAll()

        XCTAssertTrue(try store.entries().isEmpty)
    }

    func testEvictsOldestNonPinnedEntryAtCapacity() throws {
        let store = try makeInMemoryStore()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        for index in 0..<ClipboardHistoryStore.maximumEntryCount {
            _ = try store.capture(
                clip(index),
                at: baseDate.addingTimeInterval(TimeInterval(index))
            )
        }

        let oldest = try XCTUnwrap(store.entries().last)
        oldest.pinned = true
        try store.modelContainer.mainContext.save()

        _ = try store.capture(
            clip(ClipboardHistoryStore.maximumEntryCount),
            at: baseDate.addingTimeInterval(1_000)
        )

        let entries = try store.entries()
        XCTAssertEqual(entries.count, ClipboardHistoryStore.maximumEntryCount)
        XCTAssertTrue(entries.contains(where: { $0.id == oldest.id }))
        XCTAssertFalse(entries.contains(where: {
            $0.preview == "Clip 1"
        }))
    }

    func testPersistentContainerReopensStoredHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryStoreTests-\(UUID())")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("History.store")

        do {
            let configuration = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(
                for: ClipEntry.self,
                configurations: configuration
            )
            let store = ClipboardHistoryStore(modelContainer: container)
            _ = try store.capture(clip(42))
            XCTAssertEqual(try store.entries().count, 1)
        }

        let reopenedConfiguration = ModelConfiguration(url: storeURL)
        let reopenedContainer = try ModelContainer(
            for: ClipEntry.self,
            configurations: reopenedConfiguration
        )
        let reopenedStore = ClipboardHistoryStore(
            modelContainer: reopenedContainer
        )

        XCTAssertEqual(try reopenedStore.entries().map(\.preview), ["Clip 42"])
    }

    func testMonitorPollsOnlyAfterPasteboardChangeAndStopsTimer() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("ClipboardMonitorTests-\(UUID())")
        )
        pasteboard.clearContents()
        let store = try makeInMemoryStore()
        var historyChangeCount = 0
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            historyStore: store,
            pollingInterval: 60,
            onHistoryChange: { historyChangeCount += 1 }
        )

        monitor.poll()
        XCTAssertTrue(try store.entries().isEmpty)
        XCTAssertEqual(historyChangeCount, 0)

        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("captured", forType: .string)
        monitor.poll()
        XCTAssertEqual(try store.entries().map(\.preview), ["captured"])
        XCTAssertEqual(historyChangeCount, 1)

        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }

    func testDiscardPendingPasteboardChangePreventsReimportAfterDeleteAll() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("ClipboardMonitorClearTests-\(UUID())")
        )
        pasteboard.clearContents()
        let store = try makeInMemoryStore()
        _ = try store.capture(clip(1))
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            historyStore: store
        )

        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("pending clipboard text", forType: .string)
        monitor.discardPendingPasteboardChange()
        try store.deleteAll()
        monitor.poll()

        XCTAssertTrue(try store.entries().isEmpty)
    }

    private func makeInMemoryStore() throws -> ClipboardHistoryStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ClipEntry.self,
            configurations: configuration
        )
        return ClipboardHistoryStore(modelContainer: container)
    }

    private func clip(_ index: Int) -> CapturedClip {
        CapturedClip(
            kind: .text,
            preview: "Clip \(index)",
            data: Data("content-\(index)".utf8)
        )
    }
}
