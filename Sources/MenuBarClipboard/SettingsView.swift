import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isRecording = false
    @State private var isRecordingScreenshot = false
    @State private var isRecordingFullScreenshot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Picker shortcut")
                    .font(.system(size: 13, weight: .semibold))

                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isRecording ? Color.accentColor : Color.secondary.opacity(0.4),
                            lineWidth: isRecording ? 2 : 1
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.04))
                        )

                    Text(fieldLabel)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(isRecording ? .secondary : .primary)

                    ShortcutRecorderView(isRecording: $isRecording) { shortcut in
                        viewModel.record(shortcut)
                    }
                }
                .frame(height: 34)
            }

            statusLine

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Screenshot shortcuts")
                    .font(.system(size: 13, weight: .semibold))

                HStack {
                    Text("Selected area")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Reset") {
                        viewModel.resetScreenshotShortcut()
                    }
                    .controlSize(.small)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isRecordingScreenshot
                                ? Color.accentColor
                                : Color.secondary.opacity(0.4),
                            lineWidth: isRecordingScreenshot ? 2 : 1
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.04))
                        )

                    Text(
                        isRecordingScreenshot
                            ? "Press a shortcut…"
                            : viewModel.screenshotShortcut.displayString
                    )
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(
                        isRecordingScreenshot ? .secondary : .primary
                    )

                    ShortcutRecorderView(
                        isRecording: $isRecordingScreenshot
                    ) { shortcut in
                        viewModel.recordScreenshotShortcut(shortcut)
                    }
                }
                .frame(height: 34)

                Text("Opens Apple’s area selector and copies the screenshot directly into history.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if let message = viewModel.screenshotShortcutMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Full screen")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Reset") {
                        viewModel.resetFullScreenshotShortcut()
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)

                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isRecordingFullScreenshot
                                ? Color.accentColor
                                : Color.secondary.opacity(0.4),
                            lineWidth: isRecordingFullScreenshot ? 2 : 1
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.04))
                        )

                    Text(
                        isRecordingFullScreenshot
                            ? "Press a shortcut…"
                            : viewModel.fullScreenshotShortcut.displayString
                    )
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(
                        isRecordingFullScreenshot ? .secondary : .primary
                    )

                    ShortcutRecorderView(
                        isRecording: $isRecordingFullScreenshot
                    ) { shortcut in
                        viewModel.recordFullScreenshotShortcut(shortcut)
                    }
                }
                .frame(height: 34)

                Text("Captures the full screen immediately and adds it to history.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if let message = viewModel.fullScreenshotShortcutMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Button("Open macOS Keyboard Settings…") {
                    guard let url = URL(
                        string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
                    ) else { return }
                    NSWorkspace.shared.open(url)
                }
                .controlSize(.small)
            }

            Divider()

            HStack {
                Text("Pinned entries")
                Spacer()
                Picker(
                    "Pinned entries",
                    selection: Binding(
                        get: { viewModel.pinPosition },
                        set: { viewModel.setPinPosition($0) }
                    )
                ) {
                    ForEach(PinPositionPreference.allCases) { position in
                        Text(position.label).tag(position)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 130)
            }

            Divider()

            HStack {
                Text("Appearance")
                Spacer()
                Picker(
                    "Appearance",
                    selection: Binding(
                        get: { viewModel.appearance },
                        set: { viewModel.setAppearance($0) }
                    )
                ) {
                    ForEach(AppearancePreference.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            Divider()

            LaunchAtLoginSettings(manager: viewModel.launchAtLogin)

            HStack {
                Button("Reset to Default") {
                    viewModel.resetToDefault()
                }
                Spacer()
                if viewModel.isAwaitingConfirmation {
                    Button("Save Anyway") {
                        viewModel.saveWithoutConfirming()
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var fieldLabel: String {
        isRecording ? "Press a shortcut…" : viewModel.currentShortcut.displayString
    }

    @ViewBuilder
    private var statusLine: some View {
        switch viewModel.status {
        case .idle:
            Text("Click the field, then press the keys you want.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

        case let .awaitingPress(shortcut, secondsLeft):
            Label(
                "Now press \(shortcut.displayString) to confirm it reaches the app (\(secondsLeft)s)",
                systemImage: "keyboard"
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

        case let .confirmed(shortcut):
            Label("\(shortcut.displayString) is active.", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)

        case let .unreachable(shortcut):
            // The failure that Cmd+Shift+V hit: registration succeeds but
            // another process consumes the keystroke first.
            Label(
                "\(shortcut.displayString) never arrived — another app is intercepting it. Try a different combo.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)

        case let .alreadyTaken(shortcut):
            Label(
                "\(shortcut.displayString) is already registered by another app.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)

        case let .registrationFailed(status):
            Label(
                "Could not register that shortcut (error \(status)).",
                systemImage: "xmark.octagon.fill"
            )
            .font(.system(size: 11))
            .foregroundStyle(.red)
        }
    }
}

@MainActor
private struct LaunchAtLoginSettings: View {
    @ObservedObject var manager: LaunchAtLoginManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                "Launch Multiclipboard at login",
                isOn: Binding(
                    get: { manager.isEnabled },
                    set: { manager.setEnabled($0) }
                )
            )

            if let message = manager.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
