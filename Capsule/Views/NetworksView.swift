import SwiftUI

/// Networks management view
struct NetworksView: View {
    @State private var networks: [NetworkInfo] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Header toolbar
            toolbar

            Divider()

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
            loadNetworks()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Networks")
                .font(.title)
                .fontWeight(.bold)

            Spacer()

            Button(action: { loadNetworks() }) {
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

    private func networkCard(_ network: NetworkInfo) -> some View {
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

                HStack(spacing: 16) {
                    Label(network.driver, systemImage: "gearshape")
                    if let containers = network.connectedContainers, !containers.isEmpty {
                        Label("\(containers.count) containers", systemImage: "cube")
                    }
                }
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
                .disabled(network.connectedContainers?.isEmpty == false || network.isDefault)
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

    private func loadNetworks() {
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            networks = simulateNetworkList()
            isLoading = false
        }
    }

    private func createNetwork() {
        // TODO: Show create network sheet
    }

    private func deleteNetwork(_ network: NetworkInfo) {
        networks.removeAll { $0.id == network.id }
    }

    private func inspectNetwork(_ network: NetworkInfo) {
        // TODO: Show network details
    }

    private func simulateNetworkList() -> [NetworkInfo] {
        return [
            NetworkInfo(
                name: "default",
                driver: "bridge",
                subnet: "192.168.64.0/24",
                connectedContainers: ["postgres-bookshelf", "redis-bookshelf"],
                isDefault: true
            ),
        ]
    }
}

// MARK: - Network Info Model

struct NetworkInfo: Identifiable {
    let id = UUID()
    let name: String
    let driver: String
    let subnet: String?
    let connectedContainers: [String]?
    let isDefault: Bool
}

#Preview {
    NetworksView()
        .frame(width: 900, height: 600)
}
