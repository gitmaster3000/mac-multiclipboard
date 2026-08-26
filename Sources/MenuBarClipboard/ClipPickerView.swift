import AppKit
import ImageIO
import SwiftUI

struct ClipPickerView: View {
    static let panelSize = CGSize(width: 380, height: 440)

    @ObservedObject var viewModel: ClipPickerViewModel
    @FocusState private var searchFieldFocused: Bool
    @State private var isConfirmingRemoveAll = false

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if isConfirmingRemoveAll {
                removeAllConfirmation
                Divider()
            }
            Divider()
            entryList
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .onChange(of: viewModel.focus) { _, focus in
            searchFieldFocused = focus == .search
        }
        .onChange(of: searchFieldFocused) { _, isFocused in
            viewModel.focus = isFocused ? .search : .list
        }
        .onChange(of: viewModel.presentationID) {
            isConfirmingRemoveAll = false
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .font(.system(size: 12, weight: .medium))
                TextField("Search clipboard", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .focused($searchFieldFocused)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }

            Button {
                isConfirmingRemoveAll = true
            } label: {
                Label("Remove All", systemImage: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.entries.isEmpty)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
    }

    private var removeAllConfirmation: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text("Remove pinned and unpinned history?")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(nsColor: .labelColor))

            Spacer()

            Button("Cancel") {
                isConfirmingRemoveAll = false
            }
            .buttonStyle(.bordered)

            Button("Remove All") {
                isConfirmingRemoveAll = false
                viewModel.deleteAll()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(Color.orange.opacity(0.10))
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
                                .id(entry.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Win+V pastes on click rather than only
                                    // moving the selection.
                                    viewModel.selectedIndex = index
                                    viewModel.pasteSelection()
                                }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: viewModel.selectedIndex) { _, index in
                    let entries = viewModel.filteredEntries
                    guard entries.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(entries[index].id)
                    }
                }
            }
        }
    }

    private func row(for entry: ClipEntry, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            leadingIcon(for: entry)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.preview)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .frame(maxHeight: 62, alignment: .topLeading)

                Text(entry.createdAt.formatted(.relative(presentation: .numeric)))
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(spacing: 4) {
                Button {
                    viewModel.togglePin(entry)
                } label: {
                    Image(systemName: entry.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            entry.pinned
                                ? .orange
                                : Color(nsColor: .secondaryLabelColor)
                        )
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(entry.pinned ? "Unpin" : "Pin")

                Button {
                    viewModel.delete(entry)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(8)
        .frame(minHeight: 60, maxHeight: 96, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.18)
                        : Color(nsColor: .controlBackgroundColor)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isSelected
                        ? Color.accentColor.opacity(0.8)
                        : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .contextMenu {
            Button(entry.pinned ? "Unpin" : "Pin") {
                viewModel.togglePin(entry)
            }
            Divider()
            Button("Delete", role: .destructive) {
                viewModel.delete(entry)
            }
        }
    }

    /// Image clips show a thumbnail in place of the kind icon, so the list
    /// stays scannable without a preview pane.
    @ViewBuilder
    private func leadingIcon(for entry: ClipEntry) -> some View {
        if entry.clipKind == .image {
            ClipImageThumbnail(data: entry.data)
        } else {
            Image(systemName: symbolName(for: entry.clipKind))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
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

private struct ClipImageThumbnail: View {
    let data: Data
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .underPageBackgroundColor))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task {
            let payload = data
            let thumbnail = await Task.detached(priority: .utility) {
                Self.makeThumbnail(from: payload)
            }.value
            guard !Task.isCancelled, let thumbnail else { return }
            image = NSImage(data: thumbnail)
        }
    }

    nonisolated private static func makeThumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 104,
                      kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary
              )
        else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
