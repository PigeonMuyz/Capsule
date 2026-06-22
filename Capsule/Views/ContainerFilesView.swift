import SwiftUI
import AppKit

/// File browser for a running container filesystem, backed by
/// `container exec <id> ls -la <path>`.
struct ContainerFilesView: View {
    let containerID: String
    let containerName: String
    let runtime: RuntimeCore

    @State private var currentPath: String = "/"
    @State private var files: [ContainerCLI.FileInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFileID: String?
    @State private var actionMessage: String?
    @State private var syncTasks: [String: Task<Void, Never>] = [:]

    var body: some View {
        VStack(spacing: 0) {
            pathBar

            Divider()

            content

            Divider()

            footer
        }
        .task(id: "\(containerID):\(currentPath)") {
            await loadFiles()
        }
        .onDisappear {
            cancelSyncTasks()
        }
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)

            Text(currentPath)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()

            Button {
                Task { await loadFiles() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .help("Refresh")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && files.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)
                Text("Unable to browse files")
                    .font(.headline)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if files.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 42))
                    .foregroundStyle(.tertiary)
                Text("No files")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                listHeader

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if currentPath != "/" {
                            parentRow
                        }

                        ForEach(files) { file in
                            fileRow(file)
                        }
                    }
                }
            }
        }
    }

    private var listHeader: some View {
        HStack(spacing: 12) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Modified")
                .frame(width: 120, alignment: .leading)
            Text("Permissions")
                .frame(width: 100, alignment: .leading)
            Text("Size")
                .frame(width: 72, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 44)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var parentRow: some View {
        Button(action: navigateUp) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.turn.up.left")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("..")
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("")
                    .frame(width: 120)
                Text("")
                    .frame(width: 100)
                Text("")
                    .frame(width: 72)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 44)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(files.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Right-click a file for actions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func fileRow(_ file: ContainerCLI.FileInfo) -> some View {
        Button {
            selectedFileID = file.id
            if file.isDirectory {
                currentPath = file.path
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconName(for: file))
                    .foregroundStyle(file.isDirectory ? .blue : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let target = file.symlinkTarget {
                        Text("-> \(target)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(file.modified)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)

                Text(file.permissions)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 100, alignment: .leading)

                Text(file.isDirectory ? "--" : formatSize(file.size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)

                if file.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                } else {
                    Color.clear.frame(width: 10, height: 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(selectedFileID == file.id ? Color.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if file.isDirectory {
                Button("Open", action: { currentPath = file.path })
            } else {
                Button("Edit in External Editor", action: { openLocalCopy(file) })
            }
            Button("Copy Path", action: { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.path, forType: .string) })
            Divider()
            Button("Delete", role: .destructive, action: { delete(file) })
        }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 44)
        }
    }

    private func loadFiles() async {
        isLoading = true
        errorMessage = nil
        do {
            files = try await runtime.listFiles(containerID: containerID, path: currentPath)
                .sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory {
                        return lhs.isDirectory && !rhs.isDirectory
                    }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
        } catch is CancellationError {
            return
        } catch {
            files = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func delete(_ file: ContainerCLI.FileInfo) {
        Task {
            do {
                try await runtime.deleteFile(containerID: containerID, path: file.path)
                actionMessage = "Deleted \(file.name)"
                await loadFiles()
            } catch {
                actionMessage = error.localizedDescription
            }
        }
    }

    private func openLocalCopy(_ file: ContainerCLI.FileInfo) {
        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Capsule", isDirectory: true)
                    .appendingPathComponent(containerID, isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                let destination = tempDir.appendingPathComponent(file.name)
                try? FileManager.default.removeItem(at: destination)
                try await runtime.copyFileFromContainer(containerID: containerID, path: file.path, destination: destination)
                NSWorkspace.shared.open(destination)
                startSync(file: file, localURL: destination)
                actionMessage = "Editing \(file.name); saves sync back automatically"
            } catch {
                actionMessage = error.localizedDescription
            }
        }
    }

    private func startSync(file: ContainerCLI.FileInfo, localURL: URL) {
        syncTasks[file.path]?.cancel()
        syncTasks[file.path] = Task {
            var lastModified = modificationDate(for: localURL)

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard FileManager.default.fileExists(atPath: localURL.path) else {
                    await MainActor.run {
                        actionMessage = "Local copy removed: \(file.name)"
                        syncTasks[file.path] = nil
                    }
                    return
                }

                let currentModified = modificationDate(for: localURL)
                guard let currentModified, currentModified != lastModified else {
                    continue
                }

                do {
                    try await runtime.copyFileToContainer(containerID: containerID, source: localURL, path: file.path)
                    lastModified = currentModified
                    await MainActor.run {
                        actionMessage = "Synced \(file.name)"
                    }
                } catch {
                    await MainActor.run {
                        actionMessage = "Sync failed for \(file.name): \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func cancelSyncTasks() {
        for task in syncTasks.values {
            task.cancel()
        }
        syncTasks.removeAll()
    }

    private func modificationDate(for url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private func navigateUp() {
        let components = currentPath.split(separator: "/")
        if components.count > 1 {
            currentPath = "/" + components.dropLast().joined(separator: "/")
        } else {
            currentPath = "/"
        }
    }

    private func iconName(for file: ContainerCLI.FileInfo) -> String {
        if file.isDirectory { return "folder.fill" }
        if file.isSymlink { return "link" }
        return "doc"
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    ContainerFilesView(containerID: "test", containerName: "test-container", runtime: RuntimeCore())
        .frame(width: 600, height: 500)
}
