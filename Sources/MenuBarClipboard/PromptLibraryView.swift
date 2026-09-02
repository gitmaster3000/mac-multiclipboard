import AppKit
import SwiftUI

// PromptLibraryView is retained only for PromptEditSheet, which is used
// inside ClipPickerView's Prompts tab.

struct PromptEditSheet: View {
    @State private var title: String
    @State private var promptBody: String
    let onSave: (String, String) -> Void
    let onDismiss: () -> Void
    private let autoTitlePlaceholder: String

    init(title: String, body: String, onSave: @escaping (String, String) -> Void, onDismiss: @escaping () -> Void) {
        _title = State(initialValue: title)
        _promptBody = State(initialValue: body)
        self.onSave = onSave
        self.onDismiss = onDismiss
        autoTitlePlaceholder = PromptEntry.autoTitle(from: body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.isEmpty && promptBody.isEmpty ? "New Prompt" : "Edit Prompt")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(
                    autoTitlePlaceholder.isEmpty ? "Auto from body" : autoTitlePlaceholder,
                    text: $title
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $promptBody)
                    .font(.system(size: 12))
                    .frame(minHeight: 120, maxHeight: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }

            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    guard !promptBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onSave(title, promptBody)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(promptBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
