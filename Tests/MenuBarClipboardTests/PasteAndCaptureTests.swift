import AppKit
import SwiftData
import XCTest
@testable import MenuBarClipboard

@MainActor
final class ClipboardMonitorRetryTests: XCTestCase {
    /// Async copy buttons clear the pasteboard first and supply data later.
    /// `changeCount` does not move for the late write, so a poll landing in
    /// between must not consume the change.
    func testCapturesDataWrittenAfterThePollThatSawAnEmptyPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RetryTests-\(UUID())"))
        pasteboard.clearContents()
        let store = try makeInMemoryStore()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, historyStore: store)

        pasteboard.clearContents()
        monitor.poll()
        XCTAssertTrue(try store.entries().isEmpty)

        pasteboard.setString("late copy", forType: .string)
        monitor.poll()

        XCTAssertEqual(try store.entries().map(\.preview), ["late copy"])
    }

    private func makeInMemoryStore() throws -> ClipboardHistoryStore {
        let container = try ModelContainer(
            for: ClipEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ClipboardHistoryStore(modelContainer: container)
    }
}

@MainActor
final class ClipboardMonitorRetryBoundsTests: XCTestCase {
    func testStopsLookingOnceTheRetryWindowCloses() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RetryBounds-\(UUID())"))
        pasteboard.clearContents()
        let container = try ModelContainer(
            for: ClipEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = ClipboardHistoryStore(modelContainer: container)
        let monitor = ClipboardMonitor(pasteboard: pasteboard, historyStore: store)

        pasteboard.clearContents()
        for _ in 0...ClipboardMonitor.maximumExtractionRetries { monitor.poll() }
        pasteboard.setString("too late", forType: .string)
        monitor.poll()

        XCTAssertTrue(try store.entries().isEmpty)
    }

    func testRestoredClipIsNotRecapturedOnLaterPolls() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RetryRestored-\(UUID())"))
        pasteboard.clearContents()
        let container = try ModelContainer(
            for: ClipEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = ClipboardHistoryStore(modelContainer: container)
        let monitor = ClipboardMonitor(pasteboard: pasteboard, historyStore: store)

        pasteboard.clearContents()
        pasteboard.setString("restored", forType: .string)
        pasteboard.setString("id", forType: PasteboardExtractor.restoredByMulticlipboardType)
        monitor.poll()
        monitor.poll()

        XCTAssertTrue(try store.entries().isEmpty)
    }
}

final class FallbackCaptureTests: XCTestCase {
    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("Fallback-\(UUID())"))
        pasteboard.clearContents()
        return pasteboard
    }

    func testCapturesLinkOnlyCopy() {
        let pasteboard = makePasteboard()
        pasteboard.setString("https://example.com/a", forType: .URL)

        let clip = PasteboardExtractor.extract(from: pasteboard)

        XCTAssertEqual(clip?.kind, .text)
        XCTAssertEqual(clip?.preview, "https://example.com/a")
    }

    func testCapturesHTMLOnlyCopyAsPlainText() {
        let pasteboard = makePasteboard()
        pasteboard.setData(Data("<p>Hello <b>there</b></p>".utf8), forType: .html)

        let clip = PasteboardExtractor.extract(from: pasteboard)

        XCTAssertEqual(clip?.kind, .text)
        XCTAssertEqual(clip?.preview, "Hello there")
    }
}

@MainActor
final class PasteboardWriteTests: XCTestCase {
    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("Write-\(UUID())"))
        pasteboard.clearContents()
        return pasteboard
    }

    func testRichTextAlsoOffersPlainTextForPlainTextOnlyApps() throws {
        let pasteboard = makePasteboard()
        let source = NSAttributedString(string: "Rich body")
        let rtf = try source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        SystemClipPaster(pasteboard: pasteboard).write(
            ClipEntry(kind: .rtf, preview: "Rich body", data: rtf)
        )

        XCTAssertEqual(pasteboard.data(forType: .rtf), rtf)
        XCTAssertEqual(pasteboard.string(forType: .string), "Rich body")
    }

    func testPlainTextWritesFullBodyNotPreview() {
        let pasteboard = makePasteboard()
        let body = String(repeating: "x", count: 2_000)

        SystemClipPaster(pasteboard: pasteboard).write(
            ClipEntry(kind: .text, preview: "short", data: Data(body.utf8))
        )

        XCTAssertEqual(pasteboard.string(forType: .string), body)
    }

    func testImageOffersPNGAndTIFFWhicheverWasCaptured() throws {
        let bitmap = try makeBitmap()
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let tiff = try XCTUnwrap(bitmap.tiffRepresentation)

        for data in [png, tiff] {
            let pasteboard = makePasteboard()
            SystemClipPaster(pasteboard: pasteboard).write(
                ClipEntry(kind: .image, preview: "Image", data: data)
            )

            XCTAssertNotNil(pasteboard.data(forType: .png))
            XCTAssertNotNil(pasteboard.data(forType: .tiff))
        }
    }

    func testRestoredImageStaysExcludedFromHistory() throws {
        let pasteboard = makePasteboard()
        let png = try XCTUnwrap(makeBitmap().representation(using: .png, properties: [:]))

        SystemClipPaster(pasteboard: pasteboard).write(
            ClipEntry(kind: .image, preview: "Image", data: png)
        )

        XCTAssertNil(PasteboardExtractor.extract(from: pasteboard))
    }
}

@MainActor
final class PasteReadinessTests: XCTestCase {
    func testWaitsWhileThisAppIsFrontmost() {
        XCTAssertFalse(SystemClipPaster.isReadyToPaste(frontmost: 1, current: 1, target: 2))
        XCTAssertFalse(SystemClipPaster.isReadyToPaste(frontmost: nil, current: 1, target: 2))
    }

    func testPastesOnlyIntoTheTargetApp() {
        XCTAssertTrue(SystemClipPaster.isReadyToPaste(frontmost: 2, current: 1, target: 2))
        XCTAssertFalse(SystemClipPaster.isReadyToPaste(frontmost: 3, current: 1, target: 2))
    }

    func testAnyOtherAppIsAcceptableWithoutAKnownTarget() {
        XCTAssertTrue(SystemClipPaster.isReadyToPaste(frontmost: 3, current: 1, target: nil))
    }
}

final class PickerFocusRoutingTests: XCTestCase {
    func testFocusedTextFieldKeepsBackspaceButStillGetsReturnAndArrows() {
        let focus = PickerFocus.effective(stored: .list, textInputActive: true)

        XCTAssertNil(PickerCommand.from(keyCode: 51, modifiers: [], focus: focus))
        XCTAssertEqual(PickerCommand.from(keyCode: 36, modifiers: [], focus: focus), .pasteSelection)
        XCTAssertEqual(PickerCommand.from(keyCode: 125, modifiers: [], focus: focus), .moveSelection(1))
    }

    func testTextInputDoesNotOverrideOverlayOrPromptFocus() {
        XCTAssertEqual(PickerFocus.effective(stored: .editing, textInputActive: true), .editing)
        XCTAssertEqual(PickerFocus.effective(stored: .prompts, textInputActive: true), .prompts)
        XCTAssertEqual(PickerFocus.effective(stored: .list, textInputActive: false), .list)
    }

    func testPromptsTabCannotDeleteOrPasteHiddenClips() {
        for key: UInt16 in [51, 36, 76, 125, 126] {
            XCTAssertNil(PickerCommand.from(keyCode: key, modifiers: [], focus: .prompts))
        }
        XCTAssertNil(PickerCommand.from(keyCode: 51, modifiers: [.command], focus: .prompts))
        XCTAssertEqual(PickerCommand.from(keyCode: 53, modifiers: [], focus: .prompts), .dismiss)
    }
}

final class ClipCategoryTests: XCTestCase {
    private func category(ofFiles paths: String...) -> ClipCategory {
        let encoded = paths
            .map { URL(fileURLWithPath: $0).absoluteString }
            .joined(separator: "\n")
        return ClipCategory.of(kind: .fileURL, preview: "", data: Data(encoded.utf8))
    }

    func testTextAndLinks() {
        XCTAssertEqual(ClipCategory.of(kind: .text, preview: "hello", data: Data()), .text)
        XCTAssertEqual(ClipCategory.of(kind: .rtf, preview: "rich", data: Data()), .text)
        XCTAssertEqual(ClipCategory.of(kind: .text, preview: " https://a.com/x\n", data: Data()), .links)
        XCTAssertEqual(ClipCategory.of(kind: .text, preview: "see https://a.com", data: Data()), .text)
        XCTAssertEqual(ClipCategory.of(kind: .text, preview: "https://a.com and more", data: Data()), .text)
    }

    func testImageClipsDoNotReadTheirData() {
        XCTAssertEqual(
            ClipCategory.of(kind: .image, preview: "", data: { XCTFail("read data"); return Data() }()),
            .images
        )
    }

    func testFilesGroupByMediaType() {
        XCTAssertEqual(category(ofFiles: "/tmp/a.mp4"), .video)
        XCTAssertEqual(category(ofFiles: "/tmp/a.MOV"), .video)
        XCTAssertEqual(category(ofFiles: "/tmp/a.mkv"), .video)
        XCTAssertEqual(category(ofFiles: "/tmp/a.mp3"), .audio)
        XCTAssertEqual(category(ofFiles: "/tmp/a.flac"), .audio)
        XCTAssertEqual(category(ofFiles: "/tmp/a.png"), .images)
        XCTAssertEqual(category(ofFiles: "/tmp/a.pdf"), .files)
        XCTAssertEqual(category(ofFiles: "/tmp/folder"), .files)
    }

    func testMixedSelectionIsFilesUnlessEveryFileMatches() {
        XCTAssertEqual(category(ofFiles: "/tmp/a.mp4", "/tmp/b.mov"), .video)
        XCTAssertEqual(category(ofFiles: "/tmp/a.mp4", "/tmp/b.mp3"), .files)
    }
}

@MainActor
final class CategoryFilterAndFullTextTests: XCTestCase {
    private final class SpyPaster: ClipPasting {
        private(set) var pasted: [ClipEntry] = []
        func paste(_ entry: ClipEntry) { pasted.append(entry) }
    }

    private func makeStore() throws -> ClipboardHistoryStore {
        let container = try ModelContainer(
            for: ClipEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ClipboardHistoryStore(modelContainer: container)
    }

    private func populatedViewModel() throws -> (ClipPickerViewModel, SpyPaster) {
        let store = try makeStore()
        let clips: [(ClipKind, String, String)] = [
            (.text, "plain note", "plain note"),
            (.text, "https://example.com", "https://example.com"),
            (.image, "Image", "image-bytes"),
            (.fileURL, "movie.mp4", URL(fileURLWithPath: "/tmp/movie.mp4").absoluteString),
            (.fileURL, "song.mp3", URL(fileURLWithPath: "/tmp/song.mp3").absoluteString),
            (.fileURL, "report.pdf", URL(fileURLWithPath: "/tmp/report.pdf").absoluteString)
        ]
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for (index, clip) in clips.enumerated() {
            _ = try store.capture(
                CapturedClip(kind: clip.0, preview: clip.1, data: Data(clip.2.utf8)),
                at: base.addingTimeInterval(TimeInterval(index))
            )
        }
        let paster = SpyPaster()
        let viewModel = ClipPickerViewModel(historyStore: store, paster: paster)
        viewModel.reload()
        return (viewModel, paster)
    }

    func testEachCategoryShowsOnlyItsClips() throws {
        let (viewModel, _) = try populatedViewModel()
        let expected: [ClipCategory: [String]] = [
            .text: ["plain note"],
            .links: ["https://example.com"],
            .images: ["Image"],
            .video: ["movie.mp4"],
            .audio: ["song.mp3"],
            .files: ["report.pdf"]
        ]

        for (category, previews) in expected {
            viewModel.categoryFilter = category
            XCTAssertEqual(viewModel.filteredEntries.map(\.preview), previews, category.rawValue)
        }

        viewModel.categoryFilter = .all
        XCTAssertEqual(viewModel.filteredEntries.count, 6)
    }

    func testFilterCombinesWithSearch() throws {
        let (viewModel, _) = try populatedViewModel()

        viewModel.categoryFilter = .video
        viewModel.searchText = "movie"
        XCTAssertEqual(viewModel.filteredEntries.map(\.preview), ["movie.mp4"])

        viewModel.searchText = "song"
        XCTAssertTrue(viewModel.filteredEntries.isEmpty)
    }

    func testChangingFilterClearsHighlightAndPresentationResetsIt() throws {
        let (viewModel, _) = try populatedViewModel()
        viewModel.selectedIndex = 3

        viewModel.categoryFilter = .audio
        XCTAssertEqual(viewModel.selectedIndex, -1)
        viewModel.handle(.moveSelection(1))
        XCTAssertEqual(viewModel.selectedEntry?.preview, "song.mp3")

        viewModel.prepareForPresentation()
        XCTAssertEqual(viewModel.categoryFilter, .all)
    }

    func testReturnAfterSearchPastesTopMatchWithNoRowHighlighted() throws {
        let (viewModel, paster) = try populatedViewModel()
        viewModel.selectedIndex = -1
        viewModel.searchText = "plain"

        viewModel.handle(.pasteSelection)

        XCTAssertEqual(paster.pasted.map(\.preview), ["plain note"])
    }

    func testReturnWithoutQueryOrHighlightPastesNothing() throws {
        let (viewModel, paster) = try populatedViewModel()
        viewModel.selectedIndex = -1

        viewModel.handle(.pasteSelection)

        XCTAssertTrue(paster.pasted.isEmpty)
    }

    func testFullTextReturnsWholeBodyBeyondPreviewCap() throws {
        let body = String(repeating: "word ", count: 500)
        let entry = ClipEntry(kind: .text, preview: String(body.prefix(480)), data: Data(body.utf8))

        XCTAssertEqual(entry.fullText, body)
    }

    func testEditingLongTextKeepsFullBodyAndBoundsPreview() throws {
        let store = try makeStore()
        let entry = try XCTUnwrap(
            store.capture(CapturedClip(kind: .text, preview: "start", data: Data("start".utf8)))
        )
        let long = String(repeating: "a", count: 2_000)

        try store.setText(long, for: entry)

        XCTAssertEqual(entry.fullText, long)
        XCTAssertEqual(entry.preview.count, PasteboardExtractor.previewCharacterLimit)
    }
}

private func makeBitmap() throws -> NSBitmapImageRep {
    try XCTUnwrap(NSBitmapImageRep(
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
}
