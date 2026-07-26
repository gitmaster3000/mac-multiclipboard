import AppKit
import Foundation

struct CapturedClip: Equatable {
    let kind: ClipKind
    let preview: String
    let data: Data
}

enum PasteboardExtractor {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static func extract(from pasteboard: NSPasteboard) -> CapturedClip? {
        let types = Set(pasteboard.types ?? [])
        guard !types.contains(concealedType), !types.contains(transientType) else {
            return nil
        }

        if let files = extractFileURLs(from: pasteboard), !files.isEmpty {
            let encodedURLs = files
                .map(\.absoluteString)
                .joined(separator: "\n")
            let preview = files
                .map(\.lastPathComponent)
                .joined(separator: ", ")
            return CapturedClip(
                kind: .fileURL,
                preview: preview,
                data: Data(encodedURLs.utf8)
            )
        }

        if let imageData = imageData(from: pasteboard) {
            let dimensions = NSImage(data: imageData)?.size
            let preview = dimensions.map {
                "Image \(Int($0.width))×\(Int($0.height))"
            } ?? "Image"
            return CapturedClip(kind: .image, preview: preview, data: imageData)
        }

        if let rtfData = pasteboard.data(forType: .rtf), !rtfData.isEmpty {
            let preview = (try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ))?.string ?? "Rich text"
            return CapturedClip(
                kind: .rtf,
                preview: normalizedPreview(preview),
                data: rtfData
            )
        }

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return CapturedClip(
                kind: .text,
                preview: normalizedPreview(string),
                data: Data(string.utf8)
            )
        }

        return nil
    }

    private static func extractFileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )?
        .compactMap { ($0 as? NSURL) as URL? }
    }

    private static func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png), !png.isEmpty {
            return png
        }
        if let tiff = pasteboard.data(forType: .tiff), !tiff.isEmpty {
            return tiff
        }
        return nil
    }

    private static func normalizedPreview(_ value: String) -> String {
        let singleLine = value
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(singleLine.prefix(160))
    }
}
