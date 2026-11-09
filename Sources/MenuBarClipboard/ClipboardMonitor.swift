import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let historyStore: ClipboardHistoryStore
    private let pollingInterval: TimeInterval
    private let onHistoryChange: () -> Void
    private var lastChangeCount: Int
    private var timer: Timer?
    private var extractionRetriesLeft = 0

    /// Polls to keep looking at one change whose data had not arrived yet.
    static let maximumExtractionRetries = 6

    var isRunning: Bool {
        timer?.isValid == true
    }

    init(
        pasteboard: NSPasteboard = .general,
        historyStore: ClipboardHistoryStore,
        pollingInterval: TimeInterval = 0.25,
        onHistoryChange: @escaping () -> Void = {}
    ) {
        self.pasteboard = pasteboard
        self.historyStore = historyStore
        self.pollingInterval = pollingInterval
        self.onHistoryChange = onHistoryChange
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }

        let timer = Timer(timeInterval: pollingInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Treats the pasteboard's current contents as already observed.
    ///
    /// Clearing history must not cause a clipboard change that was waiting for
    /// the next timer tick to be imported immediately after the clear.
    func discardPendingPasteboardChange() {
        lastChangeCount = pasteboard.changeCount
        extractionRetriesLeft = 0
    }

    func poll() {
        let changeCount = pasteboard.changeCount
        if changeCount != lastChangeCount {
            lastChangeCount = changeCount
            extractionRetriesLeft = Self.maximumExtractionRetries
        } else if extractionRetriesLeft > 0 {
            extractionRetriesLeft -= 1
        } else {
            return
        }

        // Apps can clear the pasteboard and supply data a moment later (web
        // copy buttons do), and that late write does not move `changeCount`.
        // So an empty read keeps the change open for the next few polls.
        if PasteboardExtractor.isExcludedFromHistory(pasteboard) {
            extractionRetriesLeft = 0
            return
        }
        guard let clip = PasteboardExtractor.extract(from: pasteboard) else {
            return
        }
        extractionRetriesLeft = 0

        do {
            try historyStore.capture(clip)
            onHistoryChange()
        } catch {
            NSLog("Unable to persist clipboard entry: \(error)")
        }

        let retention = HistoryRetentionPreference.load()
        try? historyStore.evictExpiredEntries(retention: retention)
    }

    deinit {
        timer?.invalidate()
    }
}
