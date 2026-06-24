import SwiftUI

/// Middle column of the Networks view: the network list. Auto-refreshes on a timer.
struct NetworksListColumn: View {
    @ObservedObject var viewModel: ContainerViewModel
    @Binding var selection: ContainerCLI.NetworkInfo?

    @State private var networks: [ContainerCLI.NetworkInfo] = []
    @State private var showingCreateSheet = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && networks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if networks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(networks) { network in
                            NetworkRow(
                                network: network,
                                isSelected: selection?.id == network.id,
                                onSelect: { selection = network },
                                onDelete: { deleteNetwork(network) }
                            )
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationTitle("Networks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingCreateSheet = true }) {
                    Image(systemName: "plus")
                }
                .help("Create Network")
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateNetworkView(onCreate: { name, driver in Task { await createNetwork(name, driver: driver) } })
        }
        .task {
            while !Task.isCancelled {
                await loadNetworks()
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
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Networks")
                .font(.title3)
                .fontWeight(.semibold)

            Button(action: { showingCreateSheet = true }) {
                Label("Create Network", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadNetworks() async {
        isLoading = true
        do {
            networks = try await viewModel.runtime.listNetworks()
        } catch {
            errorMessage = "Failed to load networks: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func createNetwork(_ name: String, driver: String) async {
        do {
            try await viewModel.runtime.createNetwork(name: name, driver: driver)
            await loadNetworks()
        } catch {
            errorMessage = "Failed to create network: \(error.localizedDescription)"
        }
    }

    private func deleteNetwork(_ network: ContainerCLI.NetworkInfo) {
        Task {
            do {
                try await viewModel.runtime.deleteNetwork(name: network.name)
                if selection?.id == network.id { selection = nil }
                await loadNetworks()
            } catch {
                errorMessage = "Failed to delete network: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Network Row

struct NetworkRow: View {
    let network: ContainerCLI.NetworkInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(network.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(network.driver)
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

// MARK: - Network Detail Panel (Picker-style tabs)

struct NetworkDetailPanel: View {
    let network: ContainerCLI.NetworkInfo

    @State private var selectedTab: DetailTab = .overview

    enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case containers = "Containers"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar: title + picker tabs
            HStack(spacing: 16) {
                // Left: Network name
                Text(network.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.leading, 20)

                Spacer()

                // Center: Picker-style tabs
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Spacer()
            }
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content area
            Group {
                switch selectedTab {
                case .overview:
                    NetworkOverviewView(network: network)
                case .containers:
                    NetworkContainersView(network: network)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Overview View

struct NetworkOverviewView: View {
    let network: ContainerCLI.NetworkInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Actions
                InfoSection(title: "Actions") {
                    HStack(spacing: 12) {
                        Button(role: .destructive, action: deleteNetwork) {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)

                        Button(action: pruneNetworks) {
                            Label("Prune Unused", systemImage: "trash.circle")
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }

                // General
                InfoSection(title: "General") {
                    InfoRow(label: "Name", value: network.name)
                    Divider()
                    InfoRow(label: "Driver", value: network.driver)
                    Divider()
                    InfoRow(label: "ID", value: String(network.id.prefix(12)))
                }

                // Networking
                if let subnet = network.subnet {
                    InfoSection(title: "Networking") {
                        InfoRow(label: "Subnet", value: subnet)
                    }
                }

                Spacer(minLength: 16)
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func deleteNetwork() {
        // TODO: Implement delete network
    }

    private func pruneNetworks() {
        // TODO: Implement prune networks
    }
}

// MARK: - Connected Containers View

struct NetworkContainersView: View {
    let network: ContainerCLI.NetworkInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connected Containers")
                    .font(.headline)

                Text("Coming soon: List all containers connected to this network with IP addresses")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Create Network View

struct CreateNetworkView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var networkName = ""
    @State private var driver = "bridge"
    @State private var isCreating = false

    let onCreate: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Network") {
                    TextField("Name", text: $networkName, prompt: Text("backend"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Picker("Driver", selection: $driver) {
                        Text("Bridge").tag("bridge")
                        Text("NAT").tag("nat")
                        Text("Host").tag("host")
                    }
                    .pickerStyle(.segmented)
                }

                if isCreating {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Creating network...")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Network")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createNetwork() }
                        .disabled(networkName.isEmpty || isCreating)
                }
            }
            .frame(width: 520, height: 300)
        }
    }

    private func createNetwork() {
        isCreating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            onCreate(networkName, driver)
            dismiss()
        }
    }
}
