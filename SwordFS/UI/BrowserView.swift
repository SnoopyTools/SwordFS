import SwiftUI
import UIKit

// MARK: - Model

final class BrowserModel: ObservableObject {
    @Published var path: String
    @Published var entries: [FileSystemService.Entry] = []
    @Published var error: String?
    @Published var isLoading = false
    @Published var preview: FileSystemService.Entry?

    private let fs = FileSystemService.shared

    init(path: String) {
        self.path = path
        reload()
    }

    var canGoUp: Bool { path != "/" }

    var parent: String {
        guard canGoUp else { return "/" }
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let parent = (trimmed as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    func reload() {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try fs.list(path)
            self.error = nil
        } catch {
            entries = []
            self.error = error.localizedDescription
        }
    }

    func enter(_ entry: FileSystemService.Entry) {
        if entry.isDirectory {
            path = entry.path
            reload()
        } else {
            preview = entry
        }
    }

    func goUp() {
        path = parent
        reload()
    }

    func go(to newPath: String) {
        let normalized = newPath.hasPrefix("/") ? newPath : path + "/" + newPath
        path = (normalized as NSString).standardizingPath
        reload()
    }

    func createFolder(named name: String) {
        do {
            try fs.createFolder(named: name, in: path)
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func rename(_ entry: FileSystemService.Entry, to newName: String) {
        let destination = (path as NSString).appendingPathComponent(newName)
        do {
            try fs.move(from: entry.path, to: destination)
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ entry: FileSystemService.Entry) {
        do {
            try fs.delete(entry.path)
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - View

struct BrowserView: View {
    @EnvironmentObject private var controller: ExploitController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: BrowserModel
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renameTarget: FileSystemService.Entry?
    @State private var renameName = ""
    @State private var showGoTo = false
    @State private var goToPath = ""

    init(startPath: String = "/private/var/mobile") {
        _model = StateObject(wrappedValue: BrowserModel(path: startPath))
    }

    private static let bookmarks: [(String, String)] = [
        ("App container", NSHomeDirectory()),
        ("/", "/"),
        ("/private/var", "/private/var"),
        ("/var/mobile", "/var/mobile"),
        ("/var/mobile/Media", "/var/mobile/Media"),
        ("Bundles", "/var/containers/Bundle/Application"),
        ("/System/Library", "/System/Library"),
        ("/usr", "/usr"),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.error, model.entries.isEmpty {
                    ContentUnavailableView {
                        Label("Cannot read directory", systemImage: "lock.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { model.reload() }
                    }
                } else {
                    List {
                        if !controller.isReady {
                            Label("Exploit not ready — browsing is sandbox-limited",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        ForEach(model.entries) { entry in
                            row(entry)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { model.reload() }
                    .overlay {
                        if model.entries.isEmpty && model.error == nil && !model.isLoading {
                            ContentUnavailableView("Empty directory", systemImage: "folder")
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { pathBar }
            .alert("New folder", isPresented: $showNewFolder) {
                TextField("Name", text: $newFolderName)
                Button("Create") { model.createFolder(named: newFolderName); newFolderName = "" }
                Button("Cancel", role: .cancel) { newFolderName = "" }
            }
            .alert("Rename", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Name", text: $renameName)
                Button("Rename") {
                    if let target = renameTarget { model.rename(target, to: renameName) }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            .alert("Go to path", isPresented: $showGoTo) {
                TextField("/path", text: $goToPath)
                Button("Go") { model.go(to: goToPath); goToPath = "" }
                Button("Cancel", role: .cancel) { goToPath = "" }
            }
            .sheet(item: $model.preview) { entry in
                FilePreviewView(entry: entry)
            }
        }
    }

    private var title: String {
        if model.path == "/" { return "/" }
        return (model.path as NSString).lastPathComponent
    }

    private func row(_ entry: FileSystemService.Entry) -> some View {
        Button {
            model.enter(entry)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(for: entry))
                    .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text(detail(for: entry))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                model.delete(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.path
            } label: {
                Label("Copy path", systemImage: "doc.on.doc")
            }
            Button {
                renameTarget = entry
                renameName = entry.name
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if !entry.isDirectory {
                Button {
                    model.preview = entry
                } label: {
                    Label("Preview", systemImage: "eye")
                }
            }
            Button(role: .destructive) {
                model.delete(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func icon(for entry: FileSystemService.Entry) -> String {
        if entry.isSymlink { return "arrow.up.right.square" }
        if entry.isDirectory { return "folder" }
        return "doc"
    }

    private func detail(for entry: FileSystemService.Entry) -> String {
        var parts: [String] = []
        if !entry.isDirectory {
            parts.append(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
        }
        if let modified = entry.modified {
            parts.append(modified.formatted(date: .abbreviated, time: .shortened))
        }
        parts.append(String(entry.mode, radix: 8))
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                model.goUp()
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(!model.canGoUp)

            Menu {
                Section("Bookmarks") {
                    ForEach(Self.bookmarks, id: \.1) { name, target in
                        Button(name) { model.go(to: target) }
                    }
                }
                Button {
                    UIPasteboard.general.string = model.path
                } label: {
                    Label("Copy current path", systemImage: "doc.on.doc")
                }
                Button {
                    goToPath = model.path
                    showGoTo = true
                } label: {
                    Label("Go to path…", systemImage: "arrow.right.to.line")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }

            Button {
                showNewFolder = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
        }
    }

    private var pathBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(model.path)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise").font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - Preview

struct FilePreviewView: View {
    let entry: FileSystemService.Entry
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = "Loading…"
    @State private var isBinary = false
    @State private var showHex = false

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Text(isBinary && !showHex ? hexForText : text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isBinary {
                        Toggle(isOn: $showHex) {
                            Text("Hex")
                        }
                        .toggleStyle(.button)
                    }
                    ShareLink(item: URL(fileURLWithPath: entry.path))
                }
            }
            .task { load() }
        }
    }

    private var hexForText: String {
        (try? FileSystemService.shared.read(entry.path, maxBytes: 64 * 1024))
            .map(FileSystemService.hexDump) ?? "unreadable"
    }

    private func load() {
        guard !entry.isDirectory else { text = "directory"; return }
        let data = (try? FileSystemService.shared.read(entry.path, maxBytes: 256 * 1024)) ?? Data()
        if data.isEmpty {
            text = "(empty or unreadable)"
            return
        }
        isBinary = data.prefix(4096).contains(0)
        if isBinary {
            text = FileSystemService.hexDump(data)
            showHex = true
        } else {
            text = String(data: data, encoding: .utf8)
                ?? String(decoding: data, as: UTF8.self)
        }
    }
}