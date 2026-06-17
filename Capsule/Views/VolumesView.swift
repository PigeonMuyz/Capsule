import SwiftUI

/// Volumes management view
struct VolumesView: View {
    @ObservedObject var viewModel: ContainerViewModel
    @State private var volumes: [ContainerCLI.VolumeInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header toolbar
            toolbar

            Divider()

            // Error message
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        errorMessage = nil
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
            }

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
            Task {
                await loadVolumes()
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Volumes")
                .font(.title)
                .fontWeight(.bold)

            Spacer()

            Button(action: {
                Task {
                    await loadVolumes()
                }
            }) {
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

    private func volumeCard(_ volume: ContainerCLI.VolumeInfo) -> some View {
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

                Label(volume.driver, systemImage: "gearshape")
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

    private func loadVolumes() async {
        isLoading = true
        errorMessage = nil

        do {
            volumes = try await viewModel.runtime.listVolumes()
        } catch {
            errorMessage = "Failed to load volumes: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func createVolume() {
        // TODO: Show create volume sheet
    }

    private func deleteVolume(_ volume: ContainerCLI.VolumeInfo) {
        Task {
            do {
                try await viewModel.runtime.deleteVolume(name: volume.name)
                await loadVolumes()
            } catch {
                errorMessage = "Failed to delete volume: \(error.localizedDescription)"
            }
        }
    }

    private func inspectVolume(_ volume: ContainerCLI.VolumeInfo) {
        // TODO: Show volume details
    }
}

#Preview {
    VolumesView(viewModel: ContainerViewModel())
        .frame(width: 900, height: 600)
}
