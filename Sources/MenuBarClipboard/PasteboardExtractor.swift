import AppKit
import Foundation
import ImageIO

struct CapturedClip: Equatable {
    let kind: ClipKind
    let preview: String
    let data: Data
    let deduplicationData: Data?

    init(
        kind: ClipKind,
        preview: String,
        data: Data,
        deduplicationData: Data? = nil
    ) {
        self.kind = kind
        self.preview = preview
        self.data = data
        self.deduplicationData = deduplicationData
    }
}

enum PasteboardExtractor {
    /// Bounds keep accidental editor/database dumps from freezing a menu-bar
    /// process. Ordinary large documents and high-resolution screenshots fit.
    static let maximumTextBytes = 8 * 1_024 * 1_024
    static let maximumImageBytes = 100 * 1_024 * 1_024
    static let previewCharacterLimit = 480

    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let restoredByMulticlipboardType = NSPasteboard.PasteboardType(
        "com.multiclipboard.restored-entry"
    )
    static let jpegType = NSPasteboard.PasteboardType("public.jpeg")

    static func extract(from pasteboard: NSPasteboard) -> CapturedClip? {
        let types = Set(pasteboard.types ?? [])
        guard !types.contains(concealedType),
              !types.contains(transientType),
              !types.contains(restoredByMulticlipboardType)
        else {
            return nil
        }

        if let files = extractFileURLs(from: pasteboard), !files.isEmpty {
            let encodedURLs = files.map(\.absoluteString).joined(separator: "\n")
            let preview = files.map(\.lastPathComponent).joined(separator: ", ")
            return CapturedClip(
                kind: .fileURL,
                preview: preview,
                data: Data(encodedURLs.utf8)
            )
        }

        if let imageData = imageData(from: pasteboard) {
            let dimensions = imageDimensions(from: imageData)
            let preview = dimensions.map {
                "Screenshot / image \(Int($0.width))×\(Int($0.height))"
            } ?? "Image"
            return CapturedClip(kind: .image, preview: preview, data: imageData)
        }

        if let rtfData = pasteboard.data(forType: .rtf),
           !rtfData.isEmpty,
           rtfData.count <= maximumTextBytes {
            let plainText = pasteboard.string(forType: .string)
                ?? (try? NSAttributedString(
                    data: rtfData,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                ))?.string
            let plainData = plainText.map { Data($0.utf8) }
            return CapturedClip(
                kind: .rtf,
                preview: plainData.map(preview(from:)) ?? "Rich text",
                data: rtfData,
                deduplicationData: plainData
            )
        }

        if let data = pasteboard.data(forType: .string),
           !data.isEmpty,
           data.count <= maximumTextBytes {
            return CapturedClip(
                kind: .text,
                preview: preview(from: data),
                data: data,
                deduplicationData: data
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
        for type in [NSPasteboard.PasteboardType.png, .tiff, jpegType] {
            if let data = pasteboard.data(forType: type),
               !data.isEmpty,
               data.count <= maximumImageBytes {
                return data
            }
        }
        return nil
    }

    static func imagePasteboardType(for data: Data) -> NSPasteboard.PasteboardType {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source)
        else {
            return .tiff
        }
        return NSPasteboard.PasteboardType(type as String)
    }

    private static func imageDimensions(from data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            return nil
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private static func preview(from data: Data) -> String {
        // Decode only enough bytes to fill a card. Full data is preserved for
        // paste-back, making preview work constant-time for multi-megabyte text.
        let sample = String(decoding: data.prefix(4_096), as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(sample.prefix(previewCharacterLimit))
    }
}
