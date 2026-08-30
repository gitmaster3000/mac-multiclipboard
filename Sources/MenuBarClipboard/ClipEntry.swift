import Foundation
import SwiftData

enum ClipKind: String, CaseIterable, Sendable {
    case text
    case rtf
    case image
    case fileURL
}

@Model
final class ClipEntry {
    @Attribute(.unique) var id: UUID
    var kind: String
    var preview: String
    @Attribute(.externalStorage) var data: Data
    var contentFingerprint: String?
    var createdAt: Date
    var pinned: Bool

    init(
        id: UUID = UUID(),
        kind: ClipKind,
        preview: String,
        data: Data,
        contentFingerprint: String? = nil,
        createdAt: Date = Date(),
        pinned: Bool = false
    ) {
        self.id = id
        self.kind = kind.rawValue
        self.preview = preview
        self.data = data
        self.contentFingerprint = contentFingerprint
        self.createdAt = createdAt
        self.pinned = pinned
    }

    var clipKind: ClipKind? {
        ClipKind(rawValue: kind)
    }
}
