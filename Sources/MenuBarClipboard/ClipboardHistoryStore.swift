import AppKit
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
        let descriptor = FetchDescriptor<ClipEntry>()
        let entries = try collapseDuplicates(in: modelContext.fetch(descriptor))
        let contentFingerprint = Self.contentFingerprint(
            kind: clip.kind,
            preview: clip.preview,
            data: clip.data,
            deduplicationData: clip.deduplicationData
        )

        if let existing = entries.first(where: {
            Self.contentFingerprint(for: $0) == contentFingerprint
        }) {
            // Re-copying existing content moves it to the top instead of
            // creating another row. Preserve its pin while keeping the latest
            // representation (for example, rich text replacing plain text).
            existing.kind = clip.kind.rawValue
            existing.preview = clip.preview
            existing.data = clip.data
            existing.contentFingerprint = contentFingerprint
            existing.createdAt = date
            try modelContext.save()
            return nil
        }

        let entry = ClipEntry(
            kind: clip.kind,
            preview: clip.preview,
            data: clip.data,
            contentFingerprint: contentFingerprint,
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

    func entries(
        pinPosition: PinPositionPreference = .top
    ) throws -> [ClipEntry] {
        var descriptor = FetchDescriptor<ClipEntry>()
        descriptor.includePendingChanges = true
        return try collapseDuplicates(in: modelContext.fetch(descriptor))
            .sorted {
                Self.entrySort($0, $1, pinPosition: pinPosition)
            }
    }

    func delete(_ entry: ClipEntry) throws {
        modelContext.delete(entry)
        try modelContext.save()
    }

    func deleteAll() throws {
        let entries = try modelContext.fetch(FetchDescriptor<ClipEntry>())
        entries.forEach(modelContext.delete)
        try modelContext.save()
    }

    func evictExpiredEntries(retention: HistoryRetentionPreference) throws {
        var didDelete = false
        let kindMap: [(ClipKind, RetentionDuration)] = [
            (.text, retention.text),
            (.rtf, retention.text),
            (.image, retention.images),
            (.fileURL, retention.files)
        ]
        for (kind, duration) in kindMap {
            guard let maxAge = duration.maxAge else { continue }
            let cutoff = Date().addingTimeInterval(-maxAge)
            let kindStr = kind.rawValue
            let descriptor = FetchDescriptor<ClipEntry>(
                predicate: #Predicate { $0.kind == kindStr && !$0.pinned && $0.createdAt < cutoff }
            )
            let expired = try modelContext.fetch(descriptor)
            guard !expired.isEmpty else { continue }
            expired.forEach(modelContext.delete)
            didDelete = true
        }
        if didDelete { try modelContext.save() }
    }

    func setPinned(_ pinned: Bool, for entry: ClipEntry) throws {
        entry.pinned = pinned
        try modelContext.save()
    }

    func setName(_ name: String?, for entry: ClipEntry) throws {
        entry.name = name
        try modelContext.save()
    }

    /// Replaces the text of a plain-text or rich-text clip. Rich text is
    /// demoted to plain text since the edit surface is plain, and both the
    /// stored bytes and the preview are refreshed so paste and the row title
    /// reflect the new content. The fingerprint is recomputed so future
    /// captures deduplicate against the edited text, not the original.
    func setText(_ text: String, for entry: ClipEntry) throws {
        guard entry.clipKind == .text || entry.clipKind == .rtf else { return }
        let data = Data(text.utf8)
        entry.kind = ClipKind.text.rawValue
        entry.preview = text
        entry.data = data
        entry.contentFingerprint = Self.contentFingerprint(
            kind: .text,
            preview: text,
            data: data,
            deduplicationData: nil
        )
        try modelContext.save()
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

    /// Removes legacy duplicate rows, preferring a pinned copy and then the
    /// newest copy. Text and rich text share a key based on their visible
    /// content, while binary and file entries use their exact bytes.
    private func collapseDuplicates(in entries: [ClipEntry]) throws -> [ClipEntry] {
        let preferred = entries.sorted(by: Self.duplicatePreferenceSort)
        var seen = Set<String>()
        var result: [ClipEntry] = []
        var removedAny = false

        for entry in preferred {
            if seen.insert(Self.contentFingerprint(for: entry)).inserted {
                result.append(entry)
            } else {
                modelContext.delete(entry)
                removedAny = true
            }
        }

        if removedAny {
            try modelContext.save()
        }
        return result
    }

    private static func contentFingerprint(for entry: ClipEntry) -> String {
        if let fingerprint = entry.contentFingerprint {
            return fingerprint
        }
        let fingerprint = contentFingerprint(
            kind: entry.clipKind,
            preview: entry.preview,
            data: entry.data,
            deduplicationData: nil
        )
        entry.contentFingerprint = fingerprint
        return fingerprint
    }

    private static func contentFingerprint(
        kind: ClipKind?,
        preview: String,
        data: Data,
        deduplicationData: Data?
    ) -> String {
        let category: String
        let payload: Data

        switch kind {
        case .text:
            category = "text"
            payload = deduplicationData ?? data
        case .rtf:
            category = "text"
            payload = deduplicationData ?? Data(
                ((try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                ))?.string ?? preview).utf8
            )
        case .image, .fileURL, nil:
            category = kind?.rawValue ?? "unknown"
            payload = data
        }

        return category + ":" + Data(SHA256.hash(data: payload)).base64EncodedString()
    }

    private static func entrySort(
        _ lhs: ClipEntry,
        _ rhs: ClipEntry,
        pinPosition: PinPositionPreference
    ) -> Bool {
        if lhs.pinned != rhs.pinned {
            return pinPosition == .top ? lhs.pinned : !lhs.pinned
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func duplicatePreferenceSort(
        _ lhs: ClipEntry,
        _ rhs: ClipEntry
    ) -> Bool {
        if lhs.pinned != rhs.pinned {
            return lhs.pinned && !rhs.pinned
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
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
