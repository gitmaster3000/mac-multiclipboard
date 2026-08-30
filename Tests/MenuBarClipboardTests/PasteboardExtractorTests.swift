import AppKit
import XCTest
@testable import MenuBarClipboard

final class PasteboardExtractorTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PasteboardExtractorTests-\(UUID())")
        )
        pasteboard.clearContents()
    }

    func testExtractsPlainText() {
        pasteboard.setString("first line\nsecond line", forType: .string)

        let clip = PasteboardExtractor.extract(from: pasteboard)

        XCTAssertEqual(clip?.kind, .text)
        XCTAssertEqual(clip?.preview, "first line\nsecond line")
        XCTAssertEqual(clip?.data, Data("first line\nsecond line".utf8))
    }

    func testExtractsRTFBeforePlainText() throws {
        let attributedString = NSAttributedString(string: "Rich text")
        let rtf = try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        pasteboard.declareTypes([.rtf, .string], owner: nil)
        pasteboard.setData(rtf, forType: .rtf)
        pasteboard.setString("Rich text", forType: .string)

        let clip = PasteboardExtractor.extract(from: pasteboard)

        XCTAssertEqual(clip?.kind, .rtf)
        XCTAssertEqual(clip?.preview, "Rich text")
        XCTAssertEqual(clip?.data, rtf)
    }

    func testExtractsImage() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 3,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        pasteboard.setData(png, forType: .png)

        let clip = PasteboardExtractor.extract(from: pasteboard)

        XCTAssertEqual(clip?.kind, .image)
        XCTAssertEqual(clip?.preview, "Screenshot / image 2×3")
        XCTAssertEqual(clip?.data, png)
        XCTAssertEqual(PasteboardExtractor.imagePasteboardType(for: png), .png)
    }

    func testExtractsMacOSScreenshotStyleTIFF() throws {
        let image = NSImage(size: NSSize(width: 40, height: 24))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 24).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        pasteboard.setData(tiff, forType: .tiff)

        let clip = PasteboardExtractor.extract(from: pasteboard)

        XCTAssertEqual(clip?.kind, .image)
        XCTAssertEqual(clip?.preview, "Screenshot / image 80×48")
        XCTAssertEqual(clip?.data, tiff)
        XCTAssertEqual(PasteboardExtractor.imagePasteboardType(for: tiff), .tiff)
    }

    func testLargeTextPreviewIsBoundedAndPreservesFullPayload() {
        let text = Array(repeating: "line of text", count: 10_000)
            .joined(separator: "\n")
        pasteboard.setString(text, forType: .string)

        let clip = PasteboardExtractor.extract(from: pasteboard)

        XCTAssertEqual(clip?.data, Data(text.utf8))
        XCTAssertLessThanOrEqual(
            clip?.preview.count ?? .max,
            PasteboardExtractor.previewCharacterLimit
        )
        XCTAssertTrue(clip?.preview.contains("\n") == true)
    }

    func testRejectsPathologicallyLargeTextPayload() {
        let oversized = Data(
            repeating: 120,
            count: PasteboardExtractor.maximumTextBytes + 1
        )
        pasteboard.setData(oversized, forType: .string)

        XCTAssertNil(PasteboardExtractor.extract(from: pasteboard))
    }

    func testExtractsFileURLs() {
        let first = URL(fileURLWithPath: "/tmp/first.txt")
        let second = URL(fileURLWithPath: "/tmp/second.pdf")
        pasteboard.writeObjects([first as NSURL, second as NSURL])

        let clip = PasteboardExtractor.extract(from: pasteboard)

        XCTAssertEqual(clip?.kind, .fileURL)
        XCTAssertEqual(clip?.preview, "first.txt, second.pdf")
        XCTAssertEqual(
            clip?.data,
            Data("\(first.absoluteString)\n\(second.absoluteString)".utf8)
        )
    }

    func testSkipsConcealedAndTransientItems() {
        for excludedType in [
            PasteboardExtractor.concealedType,
            PasteboardExtractor.transientType,
            PasteboardExtractor.restoredByMulticlipboardType
        ] {
            pasteboard.clearContents()
            pasteboard.declareTypes([excludedType, .string], owner: nil)
            pasteboard.setData(Data(), forType: excludedType)
            pasteboard.setString("secret", forType: .string)

            XCTAssertNil(PasteboardExtractor.extract(from: pasteboard))
        }
    }
}
