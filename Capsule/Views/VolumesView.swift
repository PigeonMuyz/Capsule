import SwiftUI

/// Volumes management view
struct VolumesView: View {
    @State private var volumes: [VolumeInfo] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Header toolbar
            toolbar

            Divider()

            // Volumes list
            if isLoading {
                ProgressView("Loading volumes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if volumes.isEmpty {
                emptyState
            } else {
                volumesList
            }
        }
        .onAppear {
            loadVolumes()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Volumes")
                .font(.title)
                .fontWeight(.bold)

            Spacer()

            Button(action: { loadVolumes() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button(action: { createVolume() }) {
                Label("Create Volume", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Volumes")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Volumes provide persistent storage for containers")
                .foregroundStyle(.secondary)

            Button(action: { createVolume() }) {
                Label("Create Volume", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Volumes List

    private var volumesList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(volumes) { volume in
                    volumeCard(volume)
                }
            }
            .padding()
        }
    }

    private func volumeCard(_ volume: VolumeInfo) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .font(.title2)
                .foregroundStyle(.purple)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(volume.name)
                    .font(.headline)

                Text(volume.mountPoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Label(formatSize(volume.size), systemImage: "externaldrive")
                    if let containers = volume.usedByContainers, !containers.isEmpty {
                        Label("\(containers.count) containers", systemImage: "cube")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button(action: {
                    inspectVolume(volume)
                }) {
                    Label("Inspect", systemImage: "info.circle")
                }

                Divider()

                Button(role: .destructive, action: {
                    deleteVolume(volume)
                }) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(volume.usedByContainers?.isEmpty == false)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func loadVolumes() {
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            volumes = simulateVolumeList()
            isLoading = false
        }
    }

    private func createVolume() {
        // TODO: Show create volume sheet
    }

    private func deleteVolume(_ volume: VolumeInfo) {
        volumes.removeAll { $0.id == volume.id }
    }

    private func inspectVolume(_ volume: VolumeInfo) {
        // TODO: Show volume details
    }

    private func simulateVolumeList() -> [VolumeInfo] {
        return [
            VolumeInfo(
                name: "postgres-data",
                mountPoint: "/var/lib/postgresql/data",
                size: 1_200_000_000,
                usedByContainers: ["postgres-bookshelf"]
            ),
            VolumeInfo(
                name: "redis-data",
                mountPoint: "/data",
                size: 45_000_000,
                usedByContainers: ["redis-bookshelf"]
            ),
        ]
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Volume Info Model

struct VolumeInfo: Identifiable {
    let id = UUID()
    let name: String
    let mountPoint: String
    let size: Int64
    let usedByContainers: [String]?
}

#Preview {
    VolumesView()
        .frame(width: 900, height: 600)
}
