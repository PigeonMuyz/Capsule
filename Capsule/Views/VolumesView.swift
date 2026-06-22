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
        .columnToolbar(title: "Volumes", addHelp: "Create Volume") { showingCreateSheet = true }
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

// MARK: - Volume Detail Panel

struct VolumeDetailPanel: View {
    let volume: ContainerCLI.VolumeInfo

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(volume.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    InfoSection(title: "General") {
                        InfoRow(label: "Name", value: volume.name)
                        InfoRow(label: "Driver", value: volume.driver)
                    }

                    InfoSection(title: "Mount Point") {
                        InfoRow(label: "Path", value: volume.mountPoint)
                    }

                    if let created = volume.createdAt {
                        InfoSection(title: "Timestamps") {
                            InfoRow(label: "Created", value: created)
                        }
                    }

                    Spacer()
                }
                .padding()
            }
        }
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
