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
            preview: "Original",
            data: Data("same bytes".utf8)
        )
        let duplicate = CapturedClip(
            kind: .rtf,
            preview: "Duplicate",
            data: Data("same bytes".utf8)
        )

        XCTAssertNotNil(try store.capture(original))
        XCTAssertNil(try store.capture(duplicate))
        XCTAssertEqual(try store.entries().count, 1)
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
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            historyStore: store,
            pollingInterval: 60
        )

        monitor.poll()
        XCTAssertTrue(try store.entries().isEmpty)

        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("captured", forType: .string)
        monitor.poll()
        XCTAssertEqual(try store.entries().map(\.preview), ["captured"])

        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
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
