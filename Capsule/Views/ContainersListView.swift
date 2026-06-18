import SwiftUI

/// Selection in the unified Containers list: either a standalone container or a
/// whole compose project group. Stores ids so it stays valid across refreshes.
enum ContainerListSelection: Hashable {
    case container(String)
    case project(String)
}

/// Native window toolbar for a middle list column: a title (+ optional subtitle)
/// and a trailing "+" button. Applied via `.columnToolbar(...)`.
struct ColumnToolbar: ViewModifier {
    let title: LocalizedStringKey
    var subtitle: String? = nil
    var addHelp: LocalizedStringKey = "Add"
    let onAdd: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .fontWeight(.semibold)
                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                    }
                    .help(addHelp)
                }
            }
    }
}

extension View {
    func columnToolbar(title: LocalizedStringKey, subtitle: String? = nil, addHelp: LocalizedStringKey = "Add", onAdd: @escaping () -> Void) -> some View {
        modifier(ColumnToolbar(title: title, subtitle: subtitle, addHelp: addHelp, onAdd: onAdd))
    }
}

/// Middle column of the three-column layout: the container list, with compose
/// projects shown as collapsible top-level groups and standalone containers as
/// sibling rows (Docker Desktop style).
struct ContainersListColumn: View {
    @ObservedObject var viewModel: ContainerViewModel
    @ObservedObject var composeManager: ComposeManager
    @Binding var selection: ContainerListSelection?

    @State private var showingAddSheet = false
    @State private var expandedProjects: Set<String> = []

    var body: some View {
        Group {
            if viewModel.containers.isEmpty && composeManager.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(composeManager.projects) { project in
                            projectGroup(project)
                        }

                        ForEach(standaloneContainers) { container in
                            containerRow(container)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .columnToolbar(title: "Containers", subtitle: statusSubtitle, addHelp: "Add container, import, or compose") {
            showingAddSheet = true
        }
        .sheet(isPresented: $showingAddSheet) {
            AddContainerView(viewModel: viewModel, composeManager: composeManager)
        }
    }

    // MARK: - Compose grouping

    /// Containers belonging to a compose project, matched by the `name-service`
    /// naming convention used by `ComposeProjectWrapper.start()`.
    private func projectContainers(_ project: ComposeManager.ComposeProjectInfo) -> [ContainerSummary] {
        viewModel.containers.filter { container in
            project.services.contains { container.name == "\(project.name)-\($0)" }
        }
    }

    private var projectContainerIDs: Set<String> {
        Set(composeManager.projects.flatMap { projectContainers($0).map(\.id) })
    }

    private var standaloneContainers: [ContainerSummary] {
        viewModel.containers.filter { !projectContainerIDs.contains($0.id) }
    }

    private var statusSubtitle: String {
        let running = viewModel.containers.filter { $0.status == .running || $0.status == .starting }.count
        return running == 0 ? NSLocalizedString("None running", comment: "") : "\(running) running"
    }

    // MARK: - Project group

    @ViewBuilder
    private func projectGroup(_ project: ComposeManager.ComposeProjectInfo) -> some View {
        let isExpanded = expandedProjects.contains(project.id)
        let isSelected = selection == .project(project.id)

        Button(action: { selection = .project(project.id) }) {
            HStack(spacing: 8) {
                Button(action: { toggleExpanded(project.id) }) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)

                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.indigo)

                Circle()
                    .fill(projectStatusColor(project.status))
                    .frame(width: 8, height: 8)

                Text(project.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(project.services.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if project.status == .stopped {
                Button("Start", action: { startProject(project) })
            } else {
                Button("Stop", action: { stopProject(project) })
            }
            Divider()
            Button("Remove (Keep Volumes)", role: .destructive, action: { removeProject(project, volumes: false) })
            Button("Remove All", role: .destructive, action: { removeProject(project, volumes: true) })
        }

        if isExpanded {
            ForEach(projectContainers(project)) { container in
                containerRow(container, indented: true)
            }
        }
    }

    // MARK: - Container row

    private func containerRow(_ container: ContainerSummary, indented: Bool = false) -> some View {
        ContainerRow(
            container: container,
            isSelected: selection == .container(container.id),
            indented: indented,
            onSelect: { selection = .container(container.id) },
            onStart: { Task { await viewModel.startContainer(id: container.id) } },
            onStop: { Task { await viewModel.stopContainer(id: container.id) } },
            onRemove: {
                Task {
                    await viewModel.deleteContainer(id: container.id)
                    if selection == .container(container.id) { selection = nil }
                }
            }
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Containers")
                .font(.title3)
                .fontWeight(.semibold)

            Button(action: { showingAddSheet = true }) {
                Label("Add Container", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func toggleExpanded(_ id: String) {
        if expandedProjects.contains(id) {
            expandedProjects.remove(id)
        } else {
            expandedProjects.insert(id)
        }
    }

    private func startProject(_ project: ComposeManager.ComposeProjectInfo) {
        Task { try? await composeManager.startProject(id: project.id) }
    }

    private func stopProject(_ project: ComposeManager.ComposeProjectInfo) {
        Task { try? await composeManager.stopProject(id: project.id) }
    }

    private func removeProject(_ project: ComposeManager.ComposeProjectInfo, volumes: Bool) {
        Task {
            try? await composeManager.removeProject(id: project.id, removeVolumes: volumes)
            if selection == .project(project.id) { selection = nil }
        }
    }

    private func projectStatusColor(_ status: ComposeManager.ComposeProjectInfo.ProjectStatus) -> Color {
        switch status {
        case .running: return .green
        case .stopped: return .gray
        case .partial: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Container Row

struct ContainerRow: View {
    let container: ContainerSummary
    let isSelected: Bool
    var indented: Bool = false
    let onSelect: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(container.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(container.image)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if container.status == .running {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill").font(.caption)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button(action: onStart) {
                        Image(systemName: "play.fill").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.leading, indented ? 32 : 12)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if container.status == .running {
                Button("Stop", action: onStop)
            } else {
                Button("Start", action: onStart)
            }
            Divider()
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    private var statusColor: Color {
        switch container.status {
        case .running: return .green
        case .starting: return .orange
        case .stopped, .created: return .gray
        case .failed: return .red
        default: return .secondary
        }
    }
}

// MARK: - Container Detail Panel

struct ContainerDetailPanel: View {
    let container: ContainerSummary
    @ObservedObject var viewModel: ContainerViewModel
    @State private var selectedTab = "info"

    var body: some View {
        VStack(spacing: 0) {
            // Header with tabs (OrbStack style - compact)
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    Text(container.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)

                        Text(container.status.displayName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 12)

                HStack(spacing: 0) {
                    TabButton(title: "Info", icon: "info.circle", isSelected: selectedTab == "info") {
                        selectedTab = "info"
                    }
                    TabButton(title: "Logs", icon: "doc.text", isSelected: selectedTab == "logs") {
                        selectedTab = "logs"
                    }
                    TabButton(title: "Terminal", icon: "terminal", isSelected: selectedTab == "terminal") {
                        selectedTab = "terminal"
                    }
                    TabButton(title: "Files", icon: "folder", isSelected: selectedTab == "files") {
                        selectedTab = "files"
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                Divider()
            }

            ScrollView {
                switch selectedTab {
                case "info":
                    InfoTabView(container: container)
                case "logs":
                    LogsTabView(container: container, viewModel: viewModel)
                case "terminal":
                    TerminalTabView(container: container)
                case "files":
                    FilesTabView(container: container)
                default:
                    EmptyView()
                }
            }
        }
    }

    private var statusColor: Color {
        switch container.status {
        case .running: return .green
        case .starting: return .orange
        case .stopped, .created: return .gray
        case .failed: return .red
        default: return .secondary
        }
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: LocalizedStringKey
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info Tab

struct InfoTabView: View {
    let container: ContainerSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoSection(title: "General") {
                InfoRow(label: "Name", value: container.name)
                InfoRow(label: "ID", value: String(container.id.prefix(12)))
                InfoRow(label: "Image", value: container.image)
                InfoRow(label: "Status", value: container.status.displayName)
            }

            InfoSection(title: "Resources") {
                InfoRow(label: "CPUs", value: "\(container.cpus)")
                InfoRow(label: "Memory", value: formatMemory(container.memoryBytes))
            }

            InfoSection(title: "Timestamps") {
                InfoRow(label: "Created", value: formatDate(container.createdAt))
                if let started = container.startedAt {
                    InfoRow(label: "Started", value: formatDate(started))
                }
            }

            Spacer()
        }
        .padding()
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Info Section

struct InfoSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)

            Spacer()
        }
    }
}

// MARK: - Logs Tab

struct LogsTabView: View {
    let container: ContainerSummary
    @ObservedObject var viewModel: ContainerViewModel
    @State private var logs: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if logs.isEmpty {
                Text("No logs yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(logs.indices, id: \.self) { index in
                    Text(logs[index])
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .task(id: container.id) {
            logs = []

            // Load existing log history.
            if let text = try? await viewModel.runtime.getContainerLogs(id: container.id, tail: 500) {
                logs = text
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                while logs.last == "" { logs.removeLast() }
            }

            // Follow new output for running containers.
            guard container.status == .running else { return }
            do {
                for try await line in viewModel.runtime.streamContainerLogs(id: container.id) {
                    logs.append(line)
                    if logs.count > 2000 { logs.removeFirst(logs.count - 2000) }
                }
            } catch {
                // Stream ended or container stopped.
            }
        }
    }
}

// MARK: - Terminal Tab

struct TerminalTabView: View {
    let container: ContainerSummary

    var body: some View {
        if container.status == .running {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        ExternalTerminal.open(command: "/usr/local/bin/container exec -it \(container.id) sh")
                    } label: {
                        Label("Open in Terminal", systemImage: "arrow.up.forward.app")
                    }
                    .controlSize(.small)
                }
                .padding(8)

                ContainerTerminalRepresentable(containerID: container.id)
                    .frame(minHeight: 420)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Container not running")
                    .foregroundStyle(.secondary)
                Text("Start the container to open a shell")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

// MARK: - Files Tab

struct FilesTabView: View {
    let container: ContainerSummary

    var body: some View {
        VStack {
            Text("File Browser")
                .foregroundStyle(.secondary)
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
