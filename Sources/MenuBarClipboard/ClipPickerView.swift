import AppKit
import SwiftUI

struct ClipPickerView: View {
    static let panelSize = CGSize(width: 340, height: 420)

    @ObservedObject var viewModel: ClipPickerViewModel
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            entryList
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onChange(of: viewModel.focus) { _, focus in
            searchFieldFocused = focus == .search
        }
        .onChange(of: searchFieldFocused) { _, isFocused in
            viewModel.focus = isFocused ? .search : .list
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFieldFocused)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    @ViewBuilder
    private var entryList: some View {
        if viewModel.filteredEntries.isEmpty {
            Text(viewModel.searchText.isEmpty ? "No clips yet" : "No matches")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
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
                    .padding(6)
                }
                .onChange(of: viewModel.selectedIndex) { _, index in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(index)
                    }
                }
            }
        }
    }

    private func row(for entry: ClipEntry, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            leadingIcon(for: entry)
                .frame(width: 26, height: 26)

            Text(entry.preview)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Text(entry.createdAt.formatted(.relative(presentation: .numeric)))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .layoutPriority(-1)
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.85) : .clear)
        )
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }

    /// Image clips show a thumbnail in place of the kind icon, so the list
    /// stays scannable without a preview pane.
    @ViewBuilder
    private func leadingIcon(for entry: ClipEntry) -> some View {
        if entry.clipKind == .image, let image = NSImage(data: entry.data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: symbolName(for: entry.clipKind))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
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
}
