import SwiftUI

/// File browser for container filesystem
struct ContainerFilesView: View {
    let containerID: String
    let containerName: String

    @State private var currentPath: String = "/"
    @State private var files: [FileItem] = []

    var body: some View {
        VStack(spacing: 0) {
            // Path breadcrumb
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)

                Text(currentPath)
                    .font(.system(.body, design: .monospaced))

                Spacer()

                Button(action: { loadFiles(path: currentPath) }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // File list
            if files.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("No files")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Parent directory
                    if currentPath != "/" {
                        Button(action: { navigateUp() }) {
                            HStack {
                                Image(systemName: "arrow.turn.up.left")
                                    .foregroundStyle(.secondary)
                                Text("..")
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Files and directories
                    ForEach(files) { file in
                        fileRow(file)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(files.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("File operations coming soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .onAppear {
            loadFiles(path: currentPath)
        }
    }

    private func fileRow(_ file: FileItem) -> some View {
        Button(action: {
            if file.isDirectory {
                navigate(to: file.name)
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                    .foregroundStyle(file.isDirectory ? .blue : .secondary)
                    .frame(width: 20)

                Text(file.name)
                    .font(.system(.body, design: .monospaced))

                Spacer()

                if !file.isDirectory {
                    Text(formatSize(file.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if file.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadFiles(path: String) {
        // Simulate file listing
        files = simulateFileList(for: path)
    }

    private func navigate(to directory: String) {
        if currentPath == "/" {
            currentPath = "/" + directory
        } else {
            currentPath = currentPath + "/" + directory
        }
        loadFiles(path: currentPath)
    }

    private func navigateUp() {
        let components = currentPath.split(separator: "/")
        if components.count > 1 {
            currentPath = "/" + components.dropLast().joined(separator: "/")
        } else {
            currentPath = "/"
        }
        loadFiles(path: currentPath)
    }

    private func simulateFileList(for path: String) -> [FileItem] {
        switch path {
        case "/":
            return [
                FileItem(name: "bin", isDirectory: true, size: 0),
                FileItem(name: "etc", isDirectory: true, size: 0),
                FileItem(name: "home", isDirectory: true, size: 0),
                FileItem(name: "root", isDirectory: true, size: 0),
                FileItem(name: "usr", isDirectory: true, size: 0),
                FileItem(name: "var", isDirectory: true, size: 0),
            ]
        case "/etc":
            return [
                FileItem(name: "hostname", isDirectory: false, size: 12),
                FileItem(name: "hosts", isDirectory: false, size: 128),
                FileItem(name: "passwd", isDirectory: false, size: 456),
                FileItem(name: "shadow", isDirectory: false, size: 342),
            ]
        case "/home":
            return [
                FileItem(name: "user", isDirectory: true, size: 0),
            ]
        default:
            return []
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
    let size: Int
}

#Preview {
    ContainerFilesView(containerID: "test", containerName: "test-container")
        .frame(width: 600, height: 500)
}
