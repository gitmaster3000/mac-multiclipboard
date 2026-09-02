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
    /// A user-assigned label. Optional so SwiftData auto-migrates existing
    /// stores (old rows read back nil). Drives the row title and, for images
    /// pasted into Finder, the file name.
    var name: String?

    init(
        id: UUID = UUID(),
        kind: ClipKind,
        preview: String,
        data: Data,
        contentFingerprint: String? = nil,
        createdAt: Date = Date(),
        pinned: Bool = false,
        name: String? = nil
    ) {
        self.id = id
        self.kind = kind.rawValue
        self.preview = preview
        self.data = data
        self.contentFingerprint = contentFingerprint
        self.createdAt = createdAt
        self.pinned = pinned
        self.name = name
    }

    var clipKind: ClipKind? {
        ClipKind(rawValue: kind)
    }

    /// What the row shows as its title: the custom name if set, else the preview.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        return preview
    }
}
