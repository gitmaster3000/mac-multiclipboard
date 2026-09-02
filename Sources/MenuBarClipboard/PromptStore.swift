import Foundation
import SwiftData

@MainActor
final class PromptStore {
    let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        modelContext = modelContainer.mainContext
    }

    convenience init() throws {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Multiclipboard", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("Prompts.store")
        let configuration = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: PromptEntry.self, configurations: configuration)
        self.init(modelContainer: container)
    }

    func all() throws -> [PromptEntry] {
        var descriptor = FetchDescriptor<PromptEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor)
    }

    func add(title: String, body: String) throws -> PromptEntry {
        let resolvedTitle = title.isEmpty ? PromptEntry.autoTitle(from: body) : title
        let entry = PromptEntry(title: resolvedTitle, body: body)
        modelContext.insert(entry)
        try modelContext.save()
        return entry
    }

    func update(_ entry: PromptEntry, title: String, body: String) throws {
        entry.title = title.isEmpty ? PromptEntry.autoTitle(from: body) : title
        entry.body = body
        try modelContext.save()
    }

    func delete(_ entry: PromptEntry) throws {
        modelContext.delete(entry)
        try modelContext.save()
    }
}
