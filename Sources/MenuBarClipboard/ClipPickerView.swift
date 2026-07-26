import AppKit
import SwiftUI

struct ClipPickerView: View {
    @ObservedObject var viewModel: ClipPickerViewModel
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            listColumn
                .frame(width: 320)
            Divider()
            previewColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 420)
        .onChange(of: viewModel.focus) { _, focus in
            searchFieldFocused = focus == .search
        }
        .onChange(of: searchFieldFocused) { _, isFocused in
            viewModel.focus = isFocused ? .search : .list
        }
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .focused($searchFieldFocused)
                .padding(8)

            Divider()

            ScrollViewReader { proxy in
                List {
                    ForEach(
                        Array(viewModel.filteredEntries.enumerated()),
                        id: \.element.id
                    ) { index, entry in
                        row(for: entry, isSelected: index == viewModel.selectedIndex)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.selectedIndex = index }
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: viewModel.selectedIndex) { _, index in
                    proxy.scrollTo(index)
                }
            }

            if viewModel.filteredEntries.isEmpty {
                Text("No clips")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func row(for entry: ClipEntry, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName(for: entry.clipKind))
                .foregroundStyle(.secondary)
            Text(entry.preview)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : .clear)
        )
    }

    @ViewBuilder
    private var previewColumn: some View {
        if let entry = viewModel.selectedEntry {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.createdAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch entry.clipKind {
                case .image:
                    if let image = NSImage(data: entry.data) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("Unreadable image")
                            .foregroundStyle(.secondary)
                    }
                case .rtf:
                    ScrollView {
                        Text(Self.plainText(fromRTF: entry.data) ?? entry.preview)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .text, .fileURL, nil:
                    ScrollView {
                        Text(String(decoding: entry.data, as: UTF8.self))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
        } else {
            Text("Nothing selected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func symbolName(for kind: ClipKind?) -> String {
        switch kind {
        case .text: "textformat"
        case .rtf: "doc.richtext"
        case .image: "photo"
        case .fileURL: "folder"
        case nil: "questionmark"
        }
    }

    private static func plainText(fromRTF data: Data) -> String? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ).string
    }
}
