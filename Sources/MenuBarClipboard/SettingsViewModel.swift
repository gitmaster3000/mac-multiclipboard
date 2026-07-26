import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case awaitingPress(ShortcutPreference, secondsLeft: Int)
        case confirmed(ShortcutPreference)
        /// Registered fine, but pressing it never reached us.
        case unreachable(ShortcutPreference)
        case alreadyTaken(ShortcutPreference)
        case registrationFailed(OSStatus)
    }

    @Published private(set) var currentShortcut: ShortcutPreference
    @Published private(set) var status: Status = .idle

    var isAwaitingConfirmation: Bool {
        if case .awaitingPress = status { return true }
        return false
    }

    private let defaults: UserDefaults
    private let probe = ShortcutProbe()
    /// `nil` unregisters the live hot key, which the probe needs so it does
    /// not collide with the app's own registration of the same combo.
    private let apply: (ShortcutPreference?) -> Void
    private var confirmation = ShortcutConfirmation()
    private var timer: Timer?

    init(
        defaults: UserDefaults = .standard,
        apply: @escaping (ShortcutPreference?) -> Void
    ) {
        self.defaults = defaults
        self.apply = apply
        currentShortcut = ShortcutPreference.load(from: defaults)
    }

    /// A combo was captured. Register it on a probe and wait for the user to
    /// press it — registration status alone cannot tell us whether the key
    /// will actually arrive.
    func record(_ shortcut: ShortcutPreference) {
        cancelConfirmation()

        // Release the live hot key first, or the probe registers the same
        // combo twice and collides with itself.
        apply(nil)

        switch probe.start(shortcut, onFire: { [weak self] in self?.handleFire() }) {
        case .registered:
            confirmation.beginAwaiting(shortcut, now: Date())
            status = .awaitingPress(shortcut, secondsLeft: Int(ShortcutConfirmation.timeout))
            startTimer()

        case .alreadyTaken:
            status = .alreadyTaken(shortcut)
            apply(currentShortcut)

        case let .failed(code):
            status = .registrationFailed(code)
            apply(currentShortcut)
        }
    }

    /// Accept the candidate without waiting for a press, for when the user
    /// cannot press the combo right now.
    func saveWithoutConfirming() {
        guard let candidate = confirmation.candidate else { return }
        commit(candidate)
    }

    func resetToDefault() {
        cancelConfirmation()
        commit(.default)
    }

    func stop() {
        cancelConfirmation()
        apply(currentShortcut)
    }

    // MARK: - Confirmation

    private func handleFire() {
        confirmation.recordFire()
        guard case let .confirmed(shortcut) = confirmation.state else { return }
        commit(shortcut)
        status = .confirmed(shortcut)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let now = Date()
        confirmation.checkDeadline(now: now)

        switch confirmation.state {
        case let .awaiting(shortcut, deadline):
            status = .awaitingPress(
                shortcut,
                secondsLeft: max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
            )
        case let .failed(shortcut):
            cancelConfirmation()
            status = .unreachable(shortcut)
            apply(currentShortcut)
        case .confirmed, .idle:
            break
        }
    }

    private func commit(_ shortcut: ShortcutPreference) {
        cancelConfirmation()
        currentShortcut = shortcut
        shortcut.save(to: defaults)
        apply(shortcut)
        status = .confirmed(shortcut)
    }

    private func cancelConfirmation() {
        timer?.invalidate()
        timer = nil
        probe.stop()
        confirmation.reset()
    }
}
