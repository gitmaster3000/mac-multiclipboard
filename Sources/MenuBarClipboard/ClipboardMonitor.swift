import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let historyStore: ClipboardHistoryStore
    private let pollingInterval: TimeInterval
    private var lastChangeCount: Int
    private var timer: Timer?

    var isRunning: Bool {
        timer?.isValid == true
    }

    init(
        pasteboard: NSPasteboard = .general,
        historyStore: ClipboardHistoryStore,
        pollingInterval: TimeInterval = 0.5
    ) {
        self.pasteboard = pasteboard
        self.historyStore = historyStore
        self.pollingInterval = pollingInterval
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

    func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard let clip = PasteboardExtractor.extract(from: pasteboard) else {
            return
        }

        do {
            try historyStore.capture(clip)
        } catch {
            NSLog("Unable to persist clipboard entry: \(error)")
        }
    }

    deinit {
        timer?.invalidate()
    }
}
