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
    @Published private(set) var screenshotShortcut: ShortcutPreference
    @Published private(set) var screenshotShortcutMessage: String?
    @Published private(set) var fullScreenshotShortcut: ShortcutPreference
    @Published private(set) var fullScreenshotShortcutMessage: String?
    @Published private(set) var pinPosition: PinPositionPreference
    @Published private(set) var appearance: AppearancePreference
    @Published private(set) var status: Status = .idle
    let launchAtLogin = LaunchAtLoginManager()

    var isAwaitingConfirmation: Bool {
        if case .awaitingPress = status { return true }
        return false
    }

    private let defaults: UserDefaults
    private let probe = ShortcutProbe()
    private let screenshotProbe = ShortcutProbe()
    private let fullScreenshotProbe = ShortcutProbe()
    /// `nil` unregisters the live hot key, which the probe needs so it does
    /// not collide with the app's own registration of the same combo.
    private let apply: (ShortcutPreference?) -> Void
    private let applyScreenshot: (ShortcutPreference?) -> Void
    private let applyFullScreenshot: (ShortcutPreference?) -> Void
    private var confirmation = ShortcutConfirmation()
    private var timer: Timer?

    init(
        defaults: UserDefaults = .standard,
        apply: @escaping (ShortcutPreference?) -> Void,
        applyScreenshot: @escaping (ShortcutPreference?) -> Void = { _ in },
        applyFullScreenshot: @escaping (ShortcutPreference?) -> Void = { _ in }
    ) {
        self.defaults = defaults
        self.apply = apply
        self.applyScreenshot = applyScreenshot
        self.applyFullScreenshot = applyFullScreenshot
        currentShortcut = ShortcutPreference.load(from: defaults)
        screenshotShortcut = ScreenshotShortcutPreference.load(from: defaults)
        fullScreenshotShortcut = FullScreenshotShortcutPreference.load(
            from: defaults
        )
        pinPosition = PinPositionPreference.load(from: defaults)
        appearance = AppearancePreference.load(from: defaults)
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

    func recordScreenshotShortcut(_ shortcut: ShortcutPreference) {
        screenshotShortcutMessage = nil
        applyScreenshot(nil)

        switch screenshotProbe.start(shortcut, onFire: {}) {
        case .registered:
            screenshotProbe.stop()
            screenshotShortcut = shortcut
            ScreenshotShortcutPreference.save(shortcut, to: defaults)
            applyScreenshot(shortcut)
            screenshotShortcutMessage = "\(shortcut.displayString) is active."

        case .alreadyTaken:
            screenshotShortcutMessage = "\(shortcut.displayString) is already used by macOS or another app."
            applyScreenshot(screenshotShortcut)

        case let .failed(code):
            screenshotShortcutMessage = "Could not register that shortcut (error \(code))."
            applyScreenshot(screenshotShortcut)
        }
    }

    func resetScreenshotShortcut() {
        recordScreenshotShortcut(ScreenshotShortcutPreference.default)
    }

    func recordFullScreenshotShortcut(_ shortcut: ShortcutPreference) {
        fullScreenshotShortcutMessage = nil
        applyFullScreenshot(nil)

        switch fullScreenshotProbe.start(shortcut, onFire: {}) {
        case .registered:
            fullScreenshotProbe.stop()
            fullScreenshotShortcut = shortcut
            FullScreenshotShortcutPreference.save(shortcut, to: defaults)
            applyFullScreenshot(shortcut)
            fullScreenshotShortcutMessage = "\(shortcut.displayString) is active."

        case .alreadyTaken:
            fullScreenshotShortcutMessage = "\(shortcut.displayString) is already used by macOS or another app."
            applyFullScreenshot(fullScreenshotShortcut)

        case let .failed(code):
            fullScreenshotShortcutMessage = "Could not register that shortcut (error \(code))."
            applyFullScreenshot(fullScreenshotShortcut)
        }
    }

    func resetFullScreenshotShortcut() {
        recordFullScreenshotShortcut(FullScreenshotShortcutPreference.default)
    }

    func setPinPosition(_ position: PinPositionPreference) {
        pinPosition = position
        position.save(to: defaults)
    }

    func setAppearance(_ appearance: AppearancePreference) {
        self.appearance = appearance
        appearance.save(to: defaults)
        appearance.apply()
    }

    func stop() {
        cancelConfirmation()
        screenshotProbe.stop()
        fullScreenshotProbe.stop()
        apply(currentShortcut)
        applyScreenshot(screenshotShortcut)
        applyFullScreenshot(fullScreenshotShortcut)
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
