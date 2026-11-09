import Foundation
import UniformTypeIdentifiers

/// The type groups offered by the picker's filter bar. Derived from a clip's
/// stored kind and content, so existing history groups without a migration.
enum ClipCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case text = "Text"
    case links = "Links"
    case images = "Images"
    case video = "Video"
    case audio = "Audio"
    case files = "Files"

    var id: String { rawValue }

    /// Containers macOS may not have a registered type for.
    private static let extraVideoExtensions: Set<String> = ["mkv", "webm", "flv"]
    private static let extraAudioExtensions: Set<String> = ["flac", "ogg", "opus"]

    /// `data` is only read for file clips, so image rows stay out of memory.
    static func of(
        kind: ClipKind?,
        preview: String,
        data: @autoclosure () -> Data
    ) -> ClipCategory {
        switch kind {
        case .image:
            return .images
        case .fileURL:
            return ofFiles(String(decoding: data(), as: UTF8.self))
        case .text, .rtf, nil:
            return isLink(preview) ? .links : .text
        }
    }

    /// A single URL and nothing else. Prose that mentions a link stays text.
    private static func isLink(_ preview: String) -> Bool {
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            return false
        }
        return !trimmed.contains { $0.isWhitespace }
    }

    /// A selection groups as a media type only when every file is that type.
    private static func ofFiles(_ encodedURLs: String) -> ClipCategory {
        let categories = Set(
            encodedURLs
                .split(whereSeparator: \.isNewline)
                .map { ofFile(pathExtension: URL(string: String($0))?.pathExtension ?? "") }
        )
        return categories.count == 1 ? categories.first! : .files
    }

    private static func ofFile(pathExtension: String) -> ClipCategory {
        let ext = pathExtension.lowercased()
        if extraVideoExtensions.contains(ext) { return .video }
        if extraAudioExtensions.contains(ext) { return .audio }
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .files }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .image) { return .images }
        return .files
    }
}

extension ClipEntry {
    var category: ClipCategory {
        ClipCategory.of(kind: clipKind, preview: preview, data: data)
    }
}
