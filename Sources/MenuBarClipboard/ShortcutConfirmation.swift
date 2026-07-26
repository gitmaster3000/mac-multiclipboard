import Foundation

/// Tracks whether a candidate shortcut actually reaches the app.
///
/// Registration status is not sufficient: a combo consumed by an event tap
/// ahead of Carbon registers with `noErr` and still never fires. The only way
/// to tell is to register it and wait for a real key press.
struct ShortcutConfirmation: Equatable {
    enum State: Equatable {
        case idle
        /// Registered and waiting for the user to press the combo.
        case awaiting(ShortcutPreference, deadline: Date)
        case confirmed(ShortcutPreference)
        /// The deadline passed without the handler firing.
        case failed(ShortcutPreference)
    }

    static let timeout: TimeInterval = 10

    private(set) var state: State = .idle

    var candidate: ShortcutPreference? {
        switch state {
        case .idle: nil
        case let .awaiting(shortcut, _): shortcut
        case let .confirmed(shortcut): shortcut
        case let .failed(shortcut): shortcut
        }
    }

    mutating func beginAwaiting(_ shortcut: ShortcutPreference, now: Date) {
        state = .awaiting(shortcut, deadline: now.addingTimeInterval(Self.timeout))
    }

    /// The registered hot key fired.
    mutating func recordFire() {
        // Only meaningful while awaiting. A stray fire after the deadline must
        // not flip a failure back to success.
        guard case let .awaiting(shortcut, _) = state else { return }
        state = .confirmed(shortcut)
    }

    mutating func checkDeadline(now: Date) {
        guard case let .awaiting(shortcut, deadline) = state, now >= deadline else {
            return
        }
        state = .failed(shortcut)
    }

    mutating func reset() {
        state = .idle
    }
}
