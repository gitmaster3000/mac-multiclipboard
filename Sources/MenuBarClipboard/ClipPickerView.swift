import AppKit
import ImageIO
import SwiftUI

enum PickerTab: String, CaseIterable {
    case history = "History"
    case prompts = "Prompts"
}

struct ClipPickerView: View {
    static let panelSize = CGSize(width: 380, height: 460)

    @ObservedObject var viewModel: ClipPickerViewModel
    /// Non-nil when the app is set to show the Prompt Library tab.
    var promptViewModel: PromptLibraryViewModel?

    @FocusState private var searchFieldFocused: Bool
    @State private var isConfirmingRemoveAll = false
    @State private var hoveredEntryID: UUID?
    @State private var hoveredPromptID: UUID?
    @State private var activeTab: PickerTab = .history
    @State private var showingAddPrompt = false
    @State private var editingPrompt: PromptEntry?
    @State private var renamingClip: ClipEntry?
    /// When set, the full text of this clip is shown in an editable overlay.
    @State private var editingClip: ClipEntry?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Tab bar — only shown when Prompt Library is enabled
                if viewModel.promptLibraryEnabled, promptViewModel != nil {
                    tabBar
                    Divider()
                }

                if activeTab == .history || promptViewModel == nil || !viewModel.promptLibraryEnabled {
                    historyContent
                } else {
                    promptContent
                }
            }
            .frame(width: Self.panelSize.width, height: Self.panelSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }

            // Inline edit overlay — avoids .sheet crash on NSPanel
            if showingAddPrompt {
                promptEditOverlay(
                    title: "",
                    body: "",
                    onSave: { t, b in promptViewModel?.add(title: t, body: b) },
                    onDismiss: { showingAddPrompt = false }
                )
            } else if let entry = editingPrompt {
                promptEditOverlay(
                    title: entry.title,
                    body: entry.body,
                    onSave: { t, b in promptViewModel?.update(entry, title: t, body: b) },
                    onDismiss: { editingPrompt = nil }
                )
            }

            // Rename a clip entry (from the ⋮ / context menu).
            if let entry = renamingClip {
                nameEditOverlay(
                    initialName: entry.name ?? "",
                    placeholder: entry.preview,
                    onSave: { newName in viewModel.rename(entry, to: newName) },
                    onDismiss: { renamingClip = nil }
                )
            }

            // View / edit the full text of a text or rich-text clip.
            if let entry = editingClip {
                clipTextEditOverlay(
                    name: entry.name ?? "",
                    text: entry.preview,
                    placeholder: entry.preview,
                    onSave: { newName, newText in
                        viewModel.editText(entry, to: newText)
                        viewModel.rename(entry, to: newName)
                    },
                    onDismiss: { editingClip = nil }
                )
            }
        }
        .onChange(of: viewModel.focus) { _, focus in
            searchFieldFocused = focus == .search
        }
        .onChange(of: searchFieldFocused) { _, isFocused in
            viewModel.focus = isFocused ? .search : .list
        }
        .onChange(of: viewModel.presentationID) {
            isConfirmingRemoveAll = false
            activeTab = .history
            renamingClip = nil
            editingClip = nil
        }
        .onChange(of: editingPrompt) { _, _ in }
    }

    @ViewBuilder
    private func promptEditOverlay(title: String, body: String, onSave: @escaping (String, String) -> Void, onDismiss: @escaping () -> Void) -> some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.92)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            PromptEditSheet(title: title, body: body, onSave: onSave, onDismiss: onDismiss)
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .transition(.opacity)
    }

    @ViewBuilder
    private func nameEditOverlay(
        initialName: String,
        placeholder: String,
        onSave: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.92)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            NameEditSheet(
                initialName: initialName,
                placeholder: placeholder,
                onSave: onSave,
                onDismiss: onDismiss
            )
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .transition(.opacity)
    }

    @ViewBuilder
    private func clipTextEditOverlay(
        name: String,
        text: String,
        placeholder: String,
        onSave: @escaping (String, String) -> Void,
        onDismiss: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.92)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            ClipTextEditSheet(
                initialName: name,
                initialText: text,
                placeholder: placeholder,
                onSave: onSave,
                onDismiss: onDismiss
            )
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .transition(.opacity)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PickerTab.allCases, id: \.self) { tab in
                Button {
                    activeTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: activeTab == tab ? .semibold : .regular))
                        .foregroundStyle(activeTab == tab ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if activeTab == tab {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 34)
        .padding(.horizontal, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - History tab

    private var historyContent: some View {
        VStack(spacing: 0) {
            searchField
            if isConfirmingRemoveAll {
                removeAllConfirmation
                Divider()
            }
            Divider()
            entryList
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
                            clipRow(for: entry, isSelected: index == viewModel.selectedIndex)
                                .id(entry.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
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

    // MARK: - Clip row

    private func clipRow(for entry: ClipEntry, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            leadingIcon(for: entry)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                if entry.clipKind == .text || entry.clipKind == .rtf {
                    // Text clips get a title line plus the actual text below,
                    // so the content is visible even when a name is set.
                    Text(textTitle(for: entry))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(entry.preview)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .lineLimit(nil)
                        .truncationMode(.tail)
                        .frame(maxHeight: 46, alignment: .topLeading)
                        .clipped()
                } else {
                    Text(entry.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .lineLimit(4)
                        .truncationMode(.tail)
                        .frame(maxHeight: 62, alignment: .topLeading)
                }

                Text(entry.createdAt.formatted(.relative(presentation: .numeric)))
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(spacing: 6) {
                Button {
                    viewModel.togglePin(entry)
                } label: {
                    Image(systemName: entry.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            entry.pinned
                                ? .orange
                                : Color(nsColor: .secondaryLabelColor)
                        )
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(entry.pinned ? "Unpin" : "Pin")

                Button {
                    viewModel.delete(entry)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete")

                moreButton(for: entry)
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
        .onHover { hovering in
            // Mouse hover moves the blue selection onto the row, matching the
            // arrow keys. On exit the selection stays put so keyboard use can
            // continue from the last hovered row. The image thumbnail keeps its
            // own hover for the side preview, which is unaffected by this.
            guard hovering,
                  let index = viewModel.filteredEntries.firstIndex(where: {
                      $0.id == entry.id
                  })
            else { return }
            viewModel.selectedIndex = index
        }
        .onDrag {
            guard entry.clipKind == .image else { return NSItemProvider() }
            let provider = NSItemProvider()
            if let tempURL = Self.writeTempImage(entry.data) {
                provider.registerFileRepresentation(
                    forTypeIdentifier: "public.file-url",
                    fileOptions: .openInPlace,
                    visibility: .all
                ) { completion in
                    completion(tempURL, true, nil)
                    return nil
                }
            }
            return provider
        }
        .contextMenu {
            if entry.clipKind == .text || entry.clipKind == .rtf {
                Button("View / Edit Text…") { editingClip = entry }
            }
            Button(entry.name == nil ? "Rename…" : "Edit Name…") { renamingClip = entry }
            Button(entry.pinned ? "Unpin" : "Pin") { viewModel.togglePin(entry) }
            if viewModel.promptLibraryEnabled && (entry.clipKind == .text || entry.clipKind == .rtf) {
                Button("Save as Prompt") { saveClipAsPrompt(entry) }
            }
            if entry.clipKind == .image {
                Button("Save Image to Downloads") { viewModel.saveImageToDownloads(entry) }
            }
            Divider()
            Button("Delete", role: .destructive) { viewModel.delete(entry) }
        }
    }

    @ViewBuilder
    private func moreButton(for entry: ClipEntry) -> some View {
        Menu {
            if entry.clipKind == .text || entry.clipKind == .rtf {
                Button {
                    editingClip = entry
                } label: {
                    Label("View / Edit Text…", systemImage: "square.and.pencil")
                }
            }
            Button {
                renamingClip = entry
            } label: {
                Label(entry.name == nil ? "Rename…" : "Edit Name…", systemImage: "pencil")
            }
            Divider()
            Button {
                shareClip(entry)
            } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            if entry.clipKind == .image {
                Button {
                    viewModel.saveImageToDownloads(entry)
                } label: {
                    Label("Save to Downloads", systemImage: "arrow.down.circle")
                }
            }
            if viewModel.promptLibraryEnabled && (entry.clipKind == .text || entry.clipKind == .rtf) {
                Button {
                    saveClipAsPrompt(entry)
                } label: {
                    Label("Save as Prompt", systemImage: "text.bubble")
                }
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26, height: 26)
        .help("More actions")
    }

    /// Persists a text/rtf clip into the Prompt Library and jumps to the
    /// Prompts tab so the result is visible. Routing through the prompt view
    /// model refreshes its list immediately.
    private func saveClipAsPrompt(_ entry: ClipEntry) {
        guard entry.clipKind == .text || entry.clipKind == .rtf else { return }
        promptViewModel?.add(title: "", body: entry.preview)
        if viewModel.promptLibraryEnabled, promptViewModel != nil {
            activeTab = .prompts
        }
    }

    private func shareClip(_ entry: ClipEntry) {
        guard let contentView = NSApp.keyWindow?.contentView else { return }
        let items: [Any]
        if entry.clipKind == .image, let image = NSImage(data: entry.data) {
            items = [image]
        } else {
            items = [entry.preview as NSString]
        }
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
    }

    // MARK: - Prompt tab

    private var promptContent: some View {
        VStack(spacing: 0) {
            promptHeader
            Divider()
            promptList
        }
    }

    private var promptHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .font(.system(size: 12, weight: .medium))
                if let pvm = promptViewModel {
                    TextField("Search prompts", text: Binding(
                        get: { pvm.searchText },
                        set: { pvm.searchText = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .labelColor))
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor), lineWidth: 1) }

            Button {
                showingAddPrompt = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .help("New Prompt")
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
    }

    @ViewBuilder
    private var promptList: some View {
        if let pvm = promptViewModel {
            if pvm.filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(pvm.searchText.isEmpty ? "No prompts yet" : "No matches")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if pvm.searchText.isEmpty {
                        Button("Add your first prompt") { showingAddPrompt = true }
                            .buttonStyle(.bordered)
                            .font(.system(size: 11))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(
                                Array(pvm.filteredEntries.enumerated()),
                                id: \.element.id
                            ) { index, entry in
                                promptRow(for: entry, isSelected: index == pvm.selectedIndex, pvm: pvm)
                                    .id(entry.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        pvm.selectedIndex = index
                                        pvm.pasteSelection()
                                        viewModel.onDismiss()
                                    }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: pvm.selectedIndex) { _, index in
                        let list = pvm.filteredEntries
                        guard list.indices.contains(index) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(list[index].id)
                        }
                    }
                }
            }
        } else {
            EmptyView()
        }
    }

    private func promptRow(for entry: PromptEntry, isSelected: Bool, pvm: PromptLibraryViewModel) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .lineLimit(1)
                Text(entry.body)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(3)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            VStack(spacing: 6) {
                Button {
                    editingPrompt = entry
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit")

                if hoveredPromptID == entry.id {
                    Button {
                        pvm.delete(entry)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
        }
        .padding(8)
        .frame(minHeight: 60, maxHeight: 96, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.8) : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredPromptID = hovering ? entry.id : nil
            }
        }
        .contextMenu {
            Button("Edit") { editingPrompt = entry }
            Divider()
            Button("Delete", role: .destructive) { pvm.delete(entry) }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func leadingIcon(for entry: ClipEntry) -> some View {
        if entry.clipKind == .image {
            ClipImageThumbnail(
                data: entry.data,
                onHoverPreview: { viewModel.onPreviewImage(entry.data) },
                onHoverEnd: { viewModel.onHidePreview() }
            )
        } else {
            Image(systemName: symbolName(for: entry))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
    }

    /// Title shown above the text preview for text/rtf clips. Uses the custom
    /// name if the user set one, otherwise the first line / few characters of
    /// the text so the row still has a heading distinct from the body.
    private func textTitle(for entry: ClipEntry) -> String {
        if let name = entry.name, !name.isEmpty { return name }
        let preview = entry.preview.lowercased()
        if preview.hasPrefix("http://") || preview.hasPrefix("https://") { return "Link" }
        return PromptEntry.autoTitle(from: entry.preview)
    }

    private func symbolName(for entry: ClipEntry) -> String {
        let preview = entry.preview.lowercased()
        let isURL = preview.hasPrefix("http://") || preview.hasPrefix("https://")
        switch entry.clipKind {
        case .rtf: return "doc.richtext"
        case .fileURL: return isURL ? "link" : "folder"
        case .text: return isURL ? "link" : "text.alignleft"
        case .image: return "photo"
        case nil: return "questionmark"
        }
    }

    static func writeTempImage(_ data: Data) -> URL? {
        let ext: String
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let type = CGImageSourceGetType(source) as? String {
            if type.contains("png") { ext = "png" }
            else if type.contains("jpeg") || type.contains("jpg") { ext = "jpg" }
            else { ext = "png" }
        } else { ext = "png" }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("multiclip-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

private struct ClipImageThumbnail: View {
    let data: Data
    var onHoverPreview: () -> Void = {}
    var onHoverEnd: () -> Void = {}
    @State private var image: NSImage?
    @State private var isHovering = false

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
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.accentColor, lineWidth: isHovering ? 2 : 0)
        }
        .scaleEffect(isHovering ? 1.06 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                onHoverPreview()
            } else {
                onHoverEnd()
            }
        }
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

/// A minimal single-field editor for naming/renaming a clip entry. Rendered as
/// an inline overlay to avoid the `.sheet`-on-NSPanel crash.
private struct NameEditSheet: View {
    @State private var name: String
    let placeholder: String
    let onSave: (String) -> Void
    let onDismiss: () -> Void

    init(
        initialName: String,
        placeholder: String,
        onSave: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _name = State(initialValue: initialName)
        self.placeholder = String(placeholder.prefix(60))
        self.onSave = onSave
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Name")
                .font(.system(size: 13, weight: .semibold))

            TextField(placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit(save)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .shadow(radius: 20)
    }

    private func save() {
        onSave(name)
        onDismiss()
    }
}

/// A full-text editor for a text/rtf clip. Lets the user read the entire clip
/// (not just the truncated row) and edit both its name and body. Rendered as an
/// inline overlay to avoid the `.sheet`-on-NSPanel crash.
private struct ClipTextEditSheet: View {
    @State private var name: String
    @State private var text: String
    let placeholder: String
    let onSave: (String, String) -> Void
    let onDismiss: () -> Void

    init(
        initialName: String,
        initialText: String,
        placeholder: String,
        onSave: @escaping (String, String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _name = State(initialValue: initialName)
        _text = State(initialValue: initialText)
        self.placeholder = String(placeholder.prefix(60))
        self.onSave = onSave
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Clip")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(placeholder.isEmpty ? "Optional name" : placeholder, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .font(.system(size: 12))
                    .frame(minHeight: 180, maxHeight: 280)
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
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onSave(name, text)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

/// The content rendered inside the standalone image-preview panel. Resizes with
/// the panel and keeps the image's aspect ratio.
struct ImagePreviewContent: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}
