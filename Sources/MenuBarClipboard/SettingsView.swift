import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isRecording = false

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
