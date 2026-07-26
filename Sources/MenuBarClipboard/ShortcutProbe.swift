import Carbon
import Foundation

/// Registers a candidate shortcut on its own so the settings window can check
/// that pressing it actually reaches this process.
///
/// `HotKey` discards the registration status and offers no way to observe a
/// single combo in isolation, so this talks to Carbon directly.
@MainActor
final class ShortcutProbe {
    enum RegistrationResult: Equatable {
        case registered
        /// Another Carbon hot key already owns the combo.
        case alreadyTaken
        case failed(OSStatus)
    }

    private static let signature: UInt32 = {
        var result: FourCharCode = 0
        for character in "MCpb".utf16 {
            result = (result << 8) + FourCharCode(character)
        }
        return result
    }()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onFire: (() -> Void)?

    func start(
        _ shortcut: ShortcutPreference,
        onFire: @escaping () -> Void
    ) -> RegistrationResult {
        stop()
        self.onFire = onFire

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let probe = Unmanaged<ShortcutProbe>.fromOpaque(userData)
                    .takeUnretainedValue()
                MainActor.assumeIsolated { probe.onFire?() }
                return noErr
            },
            1,
            &spec,
            context,
            &eventHandler
        )

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.carbonKeyCode,
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        guard status == noErr, ref != nil else {
            stop()
            return status == OSStatus(eventHotKeyExistsErr)
                ? .alreadyTaken
                : .failed(status)
        }

        hotKeyRef = ref
        return .registered
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        onFire = nil
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
