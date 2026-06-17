import SwiftUI

/// Main view displaying list of containers with grouped layout
struct ContainersListView: View {
    @ObservedObject var viewModel: ContainerViewModel
    @State private var showingCreateSheet = false
    @State private var selectedContainer: ContainerSummary?

    var body: some View {
        VStack(spacing: 0) {
            // Header toolbar
            toolbar

            Divider()

            // Container list with grouping
            if viewModel.containers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Running containers group
                        if !runningContainers.isEmpty {
                            containerGroup(
                                title: "Running",
                                count: runningContainers.count,
                                containers: runningContainers,
                                color: .green
                            )
                        }

                        // Stopped containers group
                        if !stoppedContainers.isEmpty {
                            containerGroup(
                                title: "Stopped",
                                count: stoppedContainers.count,
                                containers: stoppedContainers,
                                color: .gray
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateContainerView(viewModel: viewModel)
        }
        .sheet(item: $selectedContainer) { container in
            ContainerDetailView(container: container, viewModel: viewModel)
        }
    }

    // MARK: - Computed Properties

    private var runningContainers: [ContainerSummary] {
        viewModel.containers.filter { $0.status == .running || $0.status == .starting }
    }

    private var stoppedContainers: [ContainerSummary] {
        viewModel.containers.filter { $0.status != .running && $0.status != .starting }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
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
    }

    // MARK: - Empty State

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

    // MARK: - Container Group

    private func containerGroup(title: String, count: Int, containers: [ContainerSummary], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group header
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("(\(count))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Container cards
            VStack(spacing: 8) {
                ForEach(containers) { container in
                    containerCard(container, accentColor: color)
                }
            }
        }
    }

    // MARK: - Container Card

    private func containerCard(_ container: ContainerSummary, accentColor: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Status indicator
            Circle()
                .fill(accentColor)
                .frame(width: 10, height: 10)

            // Container info
            VStack(alignment: .leading, spacing: 4) {
                Text(container.name)
                    .font(.headline)

                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label("\(container.cpus) CPUs", systemImage: "cpu")
                    Label(container.memoryDisplayString, systemImage: "memorychip")

                    if let uptime = container.uptimeString {
                        Label(uptime, systemImage: "clock")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                if container.status.canStart {
                    Button(action: {
                        Task {
                            await viewModel.startContainer(id: container.id)
                        }
                    }) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
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
                            .font(.title2)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Stop container")
                }

                Button(action: {
                    selectedContainer = container
                }) {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("View details")

                Menu {
                    Button(role: .destructive, action: {
                        Task {
                            await viewModel.deleteContainer(id: container.id)
                        }
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(container.status.isActive)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("More actions")
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    ContainersListView(viewModel: ContainerViewModel())
        .frame(width: 900, height: 600)
}
