import SwiftUI

/// Networks management view
struct NetworksView: View {
    @ObservedObject var viewModel: ContainerViewModel
    @State private var networks: [ContainerCLI.NetworkInfo] = []
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

            // Networks list
            if isLoading {
                ProgressView("Loading networks...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if networks.isEmpty {
                emptyState
            } else {
                networksList
            }
        }
        .onAppear {
            Task {
                await loadNetworks()
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Networks")
                .font(.title)
                .fontWeight(.bold)

            Spacer()

            Button(action: {
                Task {
                    await loadNetworks()
                }
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button(action: { createNetwork() }) {
                Label("Create Network", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Networks")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Networks enable communication between containers")
                .foregroundStyle(.secondary)

            Button(action: { createNetwork() }) {
                Label("Create Network", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Networks List

    private var networksList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(networks) { network in
                    networkCard(network)
                }
            }
            .padding()
        }
    }

    private func networkCard(_ network: ContainerCLI.NetworkInfo) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "network")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(network.name)
                    .font(.headline)

                if let subnet = network.subnet {
                    Text(subnet)
                        .font(.caption)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Label(network.driver, systemImage: "gearshape")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button(action: {
                    inspectNetwork(network)
                }) {
                    Label("Inspect", systemImage: "info.circle")
                }

                Divider()

                Button(role: .destructive, action: {
                    deleteNetwork(network)
                }) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(network.name == "default")
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

    private func loadNetworks() async {
        isLoading = true
        errorMessage = nil

        do {
            networks = try await viewModel.runtime.listNetworks()
        } catch {
            errorMessage = "Failed to load networks: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func createNetwork() {
        // TODO: Show create network sheet
    }

    private func deleteNetwork(_ network: ContainerCLI.NetworkInfo) {
        Task {
            do {
                try await viewModel.runtime.deleteNetwork(name: network.name)
                await loadNetworks()
            } catch {
                errorMessage = "Failed to delete network: \(error.localizedDescription)"
            }
        }
    }

    private func inspectNetwork(_ network: ContainerCLI.NetworkInfo) {
        // TODO: Show network details
    }
}

#Preview {
    NetworksView(viewModel: ContainerViewModel())
        .frame(width: 900, height: 600)
}
