import AppKit
import SwiftUI

/// Middle column of the Volumes view: the volume list. Auto-refreshes on a timer.
struct VolumesListColumn: View {
    @ObservedObject var viewModel: ContainerViewModel
    @Binding var selection: ContainerCLI.VolumeInfo?

    @State private var volumes: [ContainerCLI.VolumeInfo] = []
    @State private var showingCreateSheet = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && volumes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if volumes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(volumes) { volume in
                            VolumeRow(
                                volume: volume,
                                isSelected: selection?.id == volume.id,
                                onSelect: { selection = volume },
                                onDelete: { deleteVolume(volume) }
                            )
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationTitle("Volumes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingCreateSheet = true }) {
                    Label("Create", systemImage: "plus")
                }
                .help("Create Volume")
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateVolumeView(onCreate: { name in Task { await createVolume(name) } })
        }
        .task {
            while !Task.isCancelled {
                await loadVolumes()
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
    }

    private var refreshInterval: Double {
        let i = UserDefaults.standard.double(forKey: "autoRefreshInterval")
        return max(i > 0 ? i : 2.0, 5)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Volumes")
                .font(.title3)
                .fontWeight(.semibold)

            Button(action: { showingCreateSheet = true }) {
                Label("Create Volume", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadVolumes() async {
        isLoading = true
        do {
            volumes = try await viewModel.runtime.listVolumes()
        } catch {
            errorMessage = "Failed to load volumes: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func createVolume(_ name: String) async {
        do {
            try await viewModel.runtime.createVolume(name: name)
            await loadVolumes()
        } catch {
            errorMessage = "Failed to create volume: \(error.localizedDescription)"
        }
    }

    private func deleteVolume(_ volume: ContainerCLI.VolumeInfo) {
        Task {
            do {
                try await viewModel.runtime.deleteVolume(name: volume.name)
                if selection?.id == volume.id { selection = nil }
                await loadVolumes()
            } catch {
                errorMessage = "Failed to delete volume: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Volume Row

struct VolumeRow: View {
    let volume: ContainerCLI.VolumeInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(volume.driver)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Volume Detail Panel (Picker-style tabs)

struct VolumeDetailPanel: View {
    let volume: ContainerCLI.VolumeInfo?
    @ObservedObject var viewModel: ContainerViewModel

    @State private var selectedTab: DetailTab = .overview

    enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case files = "Files"

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .overview: return "Overview"
            case .files: return "Files"
            }
        }
    }

    var body: some View {
        Group {
            if let volume = volume {
                switch selectedTab {
                case .overview:
                    VolumeOverviewView(volume: volume, viewModel: viewModel)
                case .files:
                    VolumeFilesView(volume: volume)
                }
            } else {
                NoSelectionView(icon: "externaldrive", message: "Select a volume to view details")
            }
        }
        .navigationTitle(volume?.name ?? "Volume")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                .disabled(volume == nil)
            }
        }
    }
}

// MARK: - Overview View

struct VolumeOverviewView: View {
    let volume: ContainerCLI.VolumeInfo
    @ObservedObject var viewModel: ContainerViewModel
    @State private var referencedContainers: [VolumeReferenceRow] = []
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                // Actions
                InfoSection(title: "Actions") {
                    HStack(spacing: 12) {
                        Button(role: .destructive, action: deleteVolume) {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isWorking)

                        Button(action: pruneVolumes) {
                            Label("Prune Unused", systemImage: "trash.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isWorking)

                        Spacer()

                        if isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                // General
                InfoSection(title: "General") {
                    InfoRow(label: "Name", value: volume.name)
                    Divider()
                    InfoRow(label: "Driver", value: volume.driver)
                }

                // Mount Point
                InfoSection(title: "Mount Point") {
                    InfoRow(label: "Path", value: volume.mountPoint)
                }

                // Timestamps
                if let created = volume.createdAt {
                    InfoSection(title: "Timestamps") {
                        InfoRow(label: "Created", value: created)
                    }
                }

                // Referenced Containers
                InfoSection(title: "Referenced By") {
                    if referencedContainers.isEmpty {
                        Text("No containers reference this volume")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(referencedContainers) { row in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(row.statusColor)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.containerName)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                    Text(row.destination)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }

                                Spacer()

                                Text(row.status.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)

                            if row.id != referencedContainers.last?.id {
                                Divider()
                            }
                        }
                    }
                }

                Spacer(minLength: 16)
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: volume.id) {
            await loadReferences()
        }
    }

    private func deleteVolume() {
        Task {
            isWorking = true
            errorMessage = nil
            do {
                try await viewModel.runtime.deleteVolume(name: volume.name)
            } catch {
                errorMessage = String.localizedStringWithFormat(
                    NSLocalizedString("Failed to delete volume: %@", comment: "Volume delete error"),
                    error.localizedDescription
                )
            }
            isWorking = false
        }
    }

    private func pruneVolumes() {
        Task {
            isWorking = true
            errorMessage = nil
            do {
                try await viewModel.runtime.pruneVolumes()
            } catch {
                errorMessage = String.localizedStringWithFormat(
                    NSLocalizedString("Failed to prune volumes: %@", comment: "Volume prune error"),
                    error.localizedDescription
                )
            }
            isWorking = false
        }
    }

    private func loadReferences() async {
        var references: [VolumeReferenceRow] = []
        for container in viewModel.containers {
            do {
                let details = try await viewModel.runtime.inspectContainer(id: container.id)
                for mount in details.configuration.mounts where mountReferencesVolume(mount) {
                    references.append(
                        VolumeReferenceRow(
                            id: "\(container.id)-\(mount.destination)",
                            containerName: container.name,
                            destination: mount.destination,
                            status: container.status
                        )
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        referencedContainers = references.sorted {
            $0.containerName.localizedCaseInsensitiveCompare($1.containerName) == .orderedAscending
        }
    }

    private func mountReferencesVolume(_ mount: ContainerCLI.ContainerDetails.Configuration.Mount) -> Bool {
        if mount.source == volume.name { return true }
        if !volume.mountPoint.isEmpty, mount.source == volume.mountPoint { return true }
        return mount.source.hasSuffix("/\(volume.name)")
    }
}

// MARK: - Files View

struct VolumeFilesView: View {
    let volume: ContainerCLI.VolumeInfo
    @State private var currentURL: URL?
    @State private var entries: [VolumeFileEntry] = []
    @State private var selectedEntryID: VolumeFileEntry.ID?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            fileToolbar

            Divider()

            if volume.mountPoint.isEmpty {
                ContentUnavailableView {
                    Label("No Mount Point", systemImage: "externaldrive.badge.questionmark")
                } description: {
                    Text("This volume does not report a host path.")
                }
            } else if isLoading && entries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Unable to Load Files", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { loadFiles() }
                }
            } else {
                Table(entries, selection: $selectedEntryID) {
                    TableColumn("Name") { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.iconName)
                                .foregroundStyle(entry.isDirectory ? .blue : .secondary)
                                .frame(width: 16)
                            Text(entry.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .width(min: 180, ideal: 320)

                    TableColumn("Date Modified") { entry in
                        Text(entry.modified)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 130, ideal: 170)

                    TableColumn("Size") { entry in
                        Text(entry.sizeDisplay)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 110)

                    TableColumn("Kind") { entry in
                        Text(entry.kind)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 90, ideal: 140)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: volume.id) {
            currentURL = URL(fileURLWithPath: volume.mountPoint, isDirectory: true)
            loadFiles()
        }
    }

    private var fileToolbar: some View {
        HStack(spacing: 8) {
            Button(action: goUp) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!canGoUp)
            .help("Back")

            Text(currentURL?.path ?? volume.mountPoint)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()

            Button(action: openSelected) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(selectedEntry == nil)
            .help("Open")

            Button(action: revealCurrentFolder) {
                Image(systemName: "finder")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(currentURL == nil)
            .help("Show in Finder")

            Button(action: loadFiles) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(isLoading || currentURL == nil)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var selectedEntry: VolumeFileEntry? {
        guard let selectedEntryID else { return nil }
        return entries.first { $0.id == selectedEntryID }
    }

    private var canGoUp: Bool {
        guard let currentURL else { return false }
        return currentURL.standardizedFileURL.path != URL(fileURLWithPath: volume.mountPoint, isDirectory: true).standardizedFileURL.path
    }

    private func loadFiles() {
        guard let currentURL else { return }
        isLoading = true
        errorMessage = nil

        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .localizedTypeDescriptionKey],
                options: []
            )

            entries = urls.compactMap(VolumeFileEntry.init(url:)).sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            selectedEntryID = nil
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func goUp() {
        guard canGoUp, let currentURL else { return }
        self.currentURL = currentURL.deletingLastPathComponent()
        loadFiles()
    }

    private func openSelected() {
        guard let selectedEntry else { return }
        if selectedEntry.isDirectory {
            currentURL = selectedEntry.url
            loadFiles()
        } else {
            NSWorkspace.shared.open(selectedEntry.url)
        }
    }

    private func revealCurrentFolder() {
        guard let currentURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([currentURL])
    }
}

private struct VolumeReferenceRow: Identifiable {
    let id: String
    let containerName: String
    let destination: String
    let status: ContainerStatus

    var statusColor: Color {
        switch status {
        case .running: return .green
        case .starting, .stopping, .creating: return .orange
        case .failed: return .red
        default: return .gray
        }
    }
}

private struct VolumeFileEntry: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
    let modifiedDate: Date?
    let size: Int64
    let kind: String

    init?(url: URL) {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .localizedTypeDescriptionKey])
            self.url = url
            self.id = url.path
            self.name = url.lastPathComponent
            self.isDirectory = values.isDirectory ?? false
            self.modifiedDate = values.contentModificationDate
            self.size = Int64(values.fileSize ?? 0)
            self.kind = values.localizedTypeDescription ?? (self.isDirectory ? String(localized: "Folder") : String(localized: "File"))
        } catch {
            return nil
        }
    }

    var iconName: String {
        isDirectory ? "folder.fill" : "doc"
    }

    var modified: String {
        guard let modifiedDate else { return "—" }
        return modifiedDate.formatted(date: .abbreviated, time: .shortened)
    }

    var sizeDisplay: String {
        if isDirectory { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - Create Volume View

struct CreateVolumeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var volumeName = ""
    @State private var purpose = "General"
    @State private var isCreating = false

    let onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Volume") {
                    TextField("Name", text: $volumeName, prompt: Text("my-volume"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Picker("Purpose", selection: $purpose) {
                        Text("General").tag("General")
                        Text("Database data").tag("Database data")
                        Text("App cache").tag("App cache")
                        Text("Static files").tag("Static files")
                    }
                }

                if isCreating {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Creating volume...")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Volume")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createVolume() }
                        .disabled(volumeName.isEmpty || isCreating)
                }
            }
            .frame(width: 520, height: 300)
        }
    }

    private func createVolume() {
        isCreating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            onCreate(volumeName)
            dismiss()
        }
    }
}
