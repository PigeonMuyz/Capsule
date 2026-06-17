import SwiftUI

/// Main view displaying list of containers
struct ContainersListView: View {
    @ObservedObject var viewModel: ContainerViewModel
    @State private var showingCreateSheet = false
    @State private var selectedContainer: ContainerSummary?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Containers")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Button(action: {
                    showingCreateSheet = true
                }) {
                    Label("New Container", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Container list
            if viewModel.containers.isEmpty {
                emptyState
            } else {
                containerList
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateContainerView(viewModel: viewModel)
        }
        .sheet(item: $selectedContainer) { container in
            ContainerDetailView(container: container, viewModel: viewModel)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Containers")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create your first container to get started")
                .foregroundStyle(.secondary)

            Button(action: {
                showingCreateSheet = true
            }) {
                Label("Create Container", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var containerList: some View {
        Table(viewModel.containers) {
            TableColumn("Name") { container in
                HStack(spacing: 8) {
                    statusIndicator(for: container.status)
                    Text(container.name)
                        .fontWeight(.medium)
                }
            }

            TableColumn("Status") { container in
                statusBadge(for: container.status)
            }

            TableColumn("Image") { container in
                Text(container.image)
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }

            TableColumn("Resources") { container in
                HStack(spacing: 12) {
                    Label("\(container.cpus) CPUs", systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(container.memoryDisplayString, systemImage: "memorychip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TableColumn("Uptime") { container in
                if let uptime = container.uptimeString {
                    Text(uptime)
                        .foregroundStyle(.secondary)
                } else {
                    Text("-")
                        .foregroundStyle(.tertiary)
                }
            }

            TableColumn("Actions") { container in
                HStack(spacing: 8) {
                    if container.status.canStart {
                        Button(action: {
                            Task {
                                await viewModel.startContainer(id: container.id)
                            }
                        }) {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .help("Start container")
                    }

                    if container.status.canStop {
                        Button(action: {
                            Task {
                                await viewModel.stopContainer(id: container.id)
                            }
                        }) {
                            Image(systemName: "stop.circle.fill")
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .help("Stop container")
                    }

                    Button(action: {
                        selectedContainer = container
                    }) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("View details")

                    Button(action: {
                        Task {
                            await viewModel.deleteContainer(id: container.id)
                        }
                    }) {
                        Image(systemName: "trash.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete container")
                    .disabled(container.status.isActive)
                }
            }
        }
    }

    private func statusIndicator(for status: ContainerStatus) -> some View {
        Circle()
            .fill(statusColor(for: status))
            .frame(width: 8, height: 8)
    }

    private func statusBadge(for status: ContainerStatus) -> some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(for: status).opacity(0.2))
            .foregroundStyle(statusColor(for: status))
            .clipShape(Capsule())
    }

    private func statusColor(for status: ContainerStatus) -> Color {
        switch status {
        case .creating, .starting:
            return .yellow
        case .running:
            return .green
        case .stopping:
            return .orange
        case .stopped, .created:
            return .gray
        case .failed:
            return .red
        }
    }
}

#Preview {
    ContainersListView(viewModel: ContainerViewModel())
        .frame(width: 900, height: 600)
}
