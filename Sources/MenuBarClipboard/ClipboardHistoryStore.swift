import CryptoKit
import Foundation
import SwiftData

@MainActor
final class ClipboardHistoryStore {
    static let maximumEntryCount = 200

    let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        modelContext = modelContainer.mainContext
    }

    convenience init() throws {
        let storeURL = try Self.persistentStoreURL()
        let configuration = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(
            for: ClipEntry.self,
            configurations: configuration
        )
        self.init(modelContainer: container)
    }

    @discardableResult
    func capture(_ clip: CapturedClip, at date: Date = Date()) throws -> ClipEntry? {
        let contentHash = SHA256.hash(data: clip.data)
        let descriptor = FetchDescriptor<ClipEntry>()
        let entries = try modelContext.fetch(descriptor)

        guard !entries.contains(where: {
            SHA256.hash(data: $0.data) == contentHash
        }) else {
            return nil
        }

        let entry = ClipEntry(
            kind: clip.kind,
            preview: clip.preview,
            data: clip.data,
            createdAt: date
        )
        modelContext.insert(entry)
        let insertedEntryWasEvicted = try evictEntriesIfNeeded(
            currentCount: entries.count + 1,
            insertedEntry: entry
        )
        try modelContext.save()
        return insertedEntryWasEvicted ? nil : entry
    }

    func entries() throws -> [ClipEntry] {
        var descriptor = FetchDescriptor<ClipEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor)
    }

    private func evictEntriesIfNeeded(
        currentCount: Int,
        insertedEntry: ClipEntry
    ) throws -> Bool {
        let overflow = currentCount - Self.maximumEntryCount
        guard overflow > 0 else { return false }

        var descriptor = FetchDescriptor<ClipEntry>(
            predicate: #Predicate { !$0.pinned },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = overflow
        let evictionCandidates = try modelContext.fetch(descriptor)
        let insertedEntryWasEvicted = evictionCandidates.contains {
            $0 === insertedEntry
        }
        evictionCandidates.forEach(modelContext.delete)
        return insertedEntryWasEvicted
    }

    private static func persistentStoreURL() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("Multiclipboard", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("History.store")
    }
}
