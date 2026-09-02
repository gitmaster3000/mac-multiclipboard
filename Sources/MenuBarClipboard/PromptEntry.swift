import Foundation
import SwiftData

@Model
final class PromptEntry {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, body: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }

    static func autoTitle(from body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.prefix(40)
        if let newline = first.firstIndex(of: "\n") {
            return String(first[..<newline])
        }
        return String(first) + (trimmed.count > 40 ? "…" : "")
    }
}
