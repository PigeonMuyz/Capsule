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
    @State private var projectPendingRemoval: ComposeManager.ComposeProjectInfo?

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.containers.isEmpty && composeManager.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if !viewModel.pendingCreations.isEmpty {
                            ForEach(viewModel.pendingCreations) { pending in
                                PendingContainerCard(pending: pending)
                            }
                        }

                        // Compose projects section
                        if !composeManager.projects.isEmpty {
                            listSectionHeader("Compose", count: composeManager.projects.count)
                            ForEach(composeManager.projects) { project in
                                projectGroup(project)
                            }
                        }

                        if !orderedStandaloneContainers.isEmpty {
                            listSectionHeader("Containers", count: orderedStandaloneContainers.count)
                            ForEach(orderedStandaloneContainers) { container in
                                containerRow(container)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationTitle("Containers")
        .navigationSubtitle(statusSubtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddSheet = true }) {
                    Label("Add", systemImage: "plus")
                }
                .help("Add container, import, or compose")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            CreateContainerPanelView(viewModel: viewModel, composeManager: composeManager)
        }
        .sheet(item: $projectPendingRemoval) { project in
            RemoveComposeProjectView(project: project, composeManager: composeManager) {
                if selection == .project(project.id) {
                    selection = nil
                }
            }
        }
        .task {
            await refreshComposeProjects()
        }
    }

    // MARK: - Compose grouping

    /// Containers belonging to a compose project, matched by the `name-service`
    /// naming convention used by `ComposeProjectWrapper.start()`.
    private func projectContainers(_ project: ComposeManager.ComposeProjectInfo) -> [ContainerSummary] {
        viewModel.containers.filter { container in
            project.services.contains { service in
                container.name == service.containerName || container.name == "\(project.name)-\(service.name)"
            }
        }
    }

    private var projectContainerIDs: Set<String> {
        Set(composeManager.projects.flatMap { projectContainers($0).map(\.id) })
    }

    private var standaloneContainers: [ContainerSummary] {
        viewModel.containers.filter { !projectContainerIDs.contains($0.id) }
    }

    private var orderedStandaloneContainers: [ContainerSummary] {
        standaloneContainers.sorted { lhs, rhs in
            if lhs.status.listPriority != rhs.status.listPriority {
                return lhs.status.listPriority < rhs.status.listPriority
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var statusSubtitle: String {
        let running = viewModel.containers.filter { $0.status == .running || $0.status == .starting }.count
        return running == 0
            ? NSLocalizedString("None running", comment: "")
            : String.localizedStringWithFormat(NSLocalizedString("%lld running", comment: "Number of running containers"), running)
    }

    // MARK: - Project group

    private func listSectionHeader(_ title: LocalizedStringKey, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func projectGroup(_ project: ComposeManager.ComposeProjectInfo) -> some View {
        let isExpanded = expandedProjects.contains(project.id)
        let isSelected = selection == .project(project.id)
        let rows = projectServiceRows(project)

        VStack(spacing: 0) {
            Button(action: {
                selection = .project(project.id)
                toggleExpanded(project.id)
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 16, height: 16)

                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.indigo)

                    Text(project.name)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Spacer()

                    Text(String.localizedStringWithFormat(NSLocalizedString("%lld services", comment: "Number of compose services"), project.serviceCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    projectStatusIndicator(project.status)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                if project.status == .creating {
                    Button("Creating") {}
                        .disabled(true)
                } else if project.status == .stopped || project.status == .error {
                    Button("Start", action: { startProject(project) })
                } else {
                    Button("Stop", action: { stopProject(project) })
                    Button("Force Stop", role: .destructive, action: { forceStopProject(project) })
                }
                Divider()
                Button("Remove...", role: .destructive, action: { projectPendingRemoval = project })
            }

            if isExpanded {
                VStack(spacing: 0) {
                    if rows.isEmpty && project.status == .creating {
                        ProjectCreatingRow()
                    }
                    ForEach(rows) { row in
                        ProjectServiceRow(
                            service: row.service,
                            container: row.container,
                            isSelected: row.container.map { selection == .container($0.id) } ?? false,
                            onSelect: {
                                if let container = row.container {
                                    selection = .container(container.id)
                                }
                            }
                        )
                        .contextMenu {
                            if let container = row.container {
                                if container.status == .running {
                                    Button("Stop") {
                                        Task { await viewModel.stopContainer(id: container.id) }
                                    }
                                    Button("Force Stop", role: .destructive) {
                                        Task { await viewModel.forceStopContainer(id: container.id) }
                                    }
                                } else if container.status.canStart {
                                    Button("Start") {
                                        Task { await viewModel.startContainer(id: container.id) }
                                    }
                                }
                                Divider()
                                Button("Remove", role: .destructive) {
                                    Task {
                                        await viewModel.deleteContainer(id: container.id)
                                        if selection == .container(container.id) { selection = nil }
                                    }
                                }
                            }
                        }

                        if row.id != rows.last?.id {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func projectServiceRows(_ project: ComposeManager.ComposeProjectInfo) -> [ProjectServiceRowData] {
        let containers = projectContainers(project)
        return project.services.map { service in
            let container = containers.first { container in
                container.name == service.containerName || container.name == "\(project.name)-\(service.name)"
            }
            return ProjectServiceRowData(service: service, container: container)
        }
    }

    // MARK: - Container row

    private func containerRow(_ container: ContainerSummary, indented: Bool = false) -> some View {
        ContainerCard(
            container: container,
            isSelected: selection == .container(container.id),
            indented: indented,
            onSelect: { selection = .container(container.id) },
            onStart: { Task { await viewModel.startContainer(id: container.id) } },
            onStop: { Task { await viewModel.stopContainer(id: container.id) } },
            onForceStop: { Task { await viewModel.forceStopContainer(id: container.id) } },
            onRemove: {
                Task {
                    await viewModel.deleteContainer(id: container.id)
                    if selection == .container(container.id) { selection = nil }
                }
            }
        )
        .id("\(container.id)-\(container.status.rawValue)")
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

    private func forceStopProject(_ project: ComposeManager.ComposeProjectInfo) {
        Task { try? await composeManager.forceStopProject(id: project.id) }
    }

    private func refreshComposeProjects() async {
        while !Task.isCancelled {
            await composeManager.refreshProjects()
            let interval = UserDefaults.standard.double(forKey: "autoRefreshInterval")
            try? await Task.sleep(for: .seconds(interval > 0 ? interval : 2.0))
        }
    }

    private func projectStatusColor(_ status: ComposeManager.ComposeProjectInfo.ProjectStatus) -> Color {
        switch status {
        case .creating: return .orange
        case .running: return .green
        case .stopped: return .gray
        case .partial: return .orange
        case .error: return .red
        }
    }

    @ViewBuilder
    private func projectStatusIndicator(_ status: ComposeManager.ComposeProjectInfo.ProjectStatus) -> some View {
        if status == .creating {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 12, height: 12)
        } else {
            Circle()
                .fill(projectStatusColor(status))
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Container Card (OrbStack-style)

struct PendingContainerCard: View {
    let pending: ContainerViewModel.PendingContainerCreation

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(pending.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(pending.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("Creating")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct ProjectCreatingRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
            Text("Creating services...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.leading, 46)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
    }
}

private struct ProjectServiceRowData: Identifiable {
    let service: ComposeManager.ComposeProjectInfo.ServiceInfo
    let container: ContainerSummary?

    var id: String { service.id }
}

struct ProjectServiceRow: View {
    let service: ComposeManager.ComposeProjectInfo.ServiceInfo
    let container: ContainerSummary?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                statusIndicator
                    .frame(width: 12, height: 12)

                Image(systemName: "cube")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(service.containerName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        Text(service.name)
                        Text(ImageDisplayHelper.simplifyRepository(container?.image ?? service.image))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(container == nil)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if let status = container?.status, status == .creating || status == .starting || status == .stopping {
            ProgressView()
                .controlSize(.mini)
        } else {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
    }

    private var statusColor: Color {
        guard let status = container?.status else { return .secondary.opacity(0.45) }
        switch status {
        case .running: return .green
        case .starting, .stopping, .creating: return .orange
        case .failed: return .red
        default: return .gray
        }
    }
}

struct ContainerCard: View {
    let container: ContainerSummary
    let isSelected: Bool
    var indented: Bool = false
    let onSelect: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onForceStop: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 状态指示灯
                statusIndicator

                VStack(alignment: .leading, spacing: 2) {
                    Text(container.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(simplifiedImageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    if container.status == .running {
                        iconAction(systemImage: "stop.fill", help: "Stop", action: onStop)
                    } else if container.status.canStart {
                        iconAction(systemImage: "play.fill", help: "Start", action: onStart)
                    }

                    iconAction(systemImage: "trash", help: "Remove", role: .destructive, action: onRemove)
                }
                .opacity(isSelected || container.status.canStart || container.status == .running ? 1 : 0.75)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, indented ? 20 : 0)
        .contextMenu {
            if container.status == .running {
                Button("Stop", action: onStop)
                Button("Force Stop", role: .destructive, action: onForceStop)
            } else if container.status.canStart {
                Button("Start", action: onStart)
            }
            Divider()
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    private var simplifiedImageName: String {
        ImageDisplayHelper.simplifyRepository(container.image)
    }

    private var statusColor: Color {
        switch container.status {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .failed: return .red
        default: return .gray
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch container.status {
        case .creating, .starting, .stopping:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
        default:
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
        }
    }

    private func iconAction(
        systemImage: String,
        help: LocalizedStringKey,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: - Container Row (Legacy - keep for compatibility)

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
        case .starting, .stopping: return .orange
        case .failed: return .red
        default: return .gray
        }
    }
}

private extension ContainerStatus {
    var listPriority: Int {
        switch self {
        case .creating, .starting, .running, .stopping:
            return 0
        case .failed:
            return 1
        case .created, .stopped:
            return 2
        }
    }
}

// MARK: - Container Detail Panel

// MARK: - SwiftLauncher-style Picker tabs

struct ContainerDetailPanel: View {
    let container: ContainerSummary?
    @ObservedObject var viewModel: ContainerViewModel

    @State private var selectedTab: DetailTab = .info

    enum DetailTab: String, CaseIterable, Identifiable {
        case info = "Info"
        case logs = "Logs"
        case terminal = "Terminal"
        case files = "Files"

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .info: return "Info"
            case .logs: return "Logs"
            case .terminal: return "Terminal"
            case .files: return "Files"
            }
        }
    }

    var body: some View {
        Group {
            if let container = container {
                switch selectedTab {
                case .info:
                    ContainerInfoView(container: container, viewModel: viewModel)
                case .logs:
                    ContainerLogsView(container: container, viewModel: viewModel)
                case .terminal:
                    ContainerTerminalView(container: container, viewModel: viewModel)
                case .files:
                    ContainerFilesView(container: container, viewModel: viewModel)
                }
            } else {
                NoSelectionView(icon: "cube", message: "Select a container to view details")
            }
        }
        .navigationTitle(container?.name ?? String(localized: "Container"))
        .navigationSubtitle(container?.image ?? "")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .disabled(container == nil)
            }
        }
    }
}

// MARK: - Info View (Container overview with controls and settings)

struct ContainerInfoView: View {
    let container: ContainerSummary
    @ObservedObject var viewModel: ContainerViewModel
    @State private var restartPolicy: RestartPolicy = .no
    @State private var autostart: Bool = false
    @State private var details: ContainerCLI.ContainerDetails?
    @State private var detailsError: String?
    @State private var generalExpanded = true
    @State private var resourcesExpanded = true
    @State private var timestampsExpanded = false
    @State private var configurationExpanded = true
    @State private var portsExpanded = true
    @State private var mountsExpanded = true
    @State private var networksExpanded = true
    @State private var restartExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overviewHeader
                controlsBar
                summaryCards
                inspectDetailsSection
                restartPolicySection
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: container.id) {
            loadRestartPolicy()
            await loadDetails()
        }
        .onChange(of: restartPolicy) { _, newValue in
            saveRestartPolicy(newValue)
        }
    }

    private var overviewHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: "cube.box.fill")
                    .font(.title2)
                    .foregroundStyle(.cyan)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(container.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ImageDisplayHelper.simplifyRepository(container.image))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(String(container.id.prefix(12)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            StatusBadge(status: container.status)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.14))
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 10) {
            Label("Controls", systemImage: "slider.horizontal.3")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if container.status == .running {
                Button(action: stopContainer) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: forceStopContainer) {
                    Label("Force Stop", systemImage: "xmark.octagon.fill")
                }
                .buttonStyle(.bordered)
            } else if container.status.canStart {
                Button(action: startContainer) {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Button(action: restartContainer) {
                Label("Restart", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(container.status != .running)

            Button(role: .destructive, action: deleteContainer) {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var summaryCards: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardPair {
                generalSection
            } trailing: {
                resourcesSection
            }

            timestampsSection
        }
    }

    private func cardPair<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                leading()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                trailing()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            VStack(alignment: .leading, spacing: 16) {
                leading()
                trailing()
            }
        }
    }

    private var generalSection: some View {
        CollapsibleInfoCard(title: "General", systemImage: "info.circle", isExpanded: $generalExpanded) {
            InfoRow(label: "Name", value: container.name)
            Divider()
            InfoRow(label: "Image", value: container.image)
            Divider()
            InfoRow(label: "Status", value: container.status.displayName)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var resourcesSection: some View {
        CollapsibleInfoCard(title: "Resources", systemImage: "gauge.with.dots.needle.bottom.50percent", isExpanded: $resourcesExpanded) {
            InfoRow(label: "CPUs", value: "\(container.cpus)")
            Divider()
            InfoRow(label: "Memory", value: formatMemory(container.memoryBytes))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var timestampsSection: some View {
        CollapsibleInfoCard(title: "Timestamps", systemImage: "clock", isExpanded: $timestampsExpanded) {
            InfoRow(label: "Created", value: formatDate(container.createdAt))
            if let started = container.startedAt {
                Divider()
                InfoRow(label: "Started", value: formatDate(started))
            }
            if let stopped = container.stoppedAt {
                Divider()
                InfoRow(label: "Stopped", value: formatDate(stopped))
            }
            if let exitCode = container.exitCode {
                Divider()
                InfoRow(label: "Exit Code", value: "\(exitCode)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var inspectDetailsSection: some View {
        if let details {
            VStack(alignment: .leading, spacing: 16) {
                cardPair {
                    configurationSection(details)
                } trailing: {
                    networksSection(details)
                }

                cardPair {
                    publishedPortsSection(details)
                } trailing: {
                    mountsSection(details)
                }
            }
        } else if let detailsError {
            CollapsibleInfoCard(title: "Details", systemImage: "exclamationmark.triangle", isExpanded: .constant(true)) {
                Text(detailsError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func configurationSection(_ details: ContainerCLI.ContainerDetails) -> some View {
        CollapsibleInfoCard(title: "Configuration", systemImage: "terminal", isExpanded: $configurationExpanded) {
            if let platform = details.configuration.platform {
                InfoRow(label: "Platform", value: platformDisplay(platform))
                Divider()
            }
            if let initProcess = details.configuration.initProcess {
                InfoRow(label: "Command", value: commandDisplay(initProcess))
                if let workingDirectory = initProcess.workingDirectory, !workingDirectory.isEmpty {
                    Divider()
                    InfoRow(label: "Working Directory", value: workingDirectory)
                }
            } else {
                InfoRow(label: "Command", value: String(localized: "Image default"))
            }

            let environment = details.configuration.initProcess?.environment ?? []
            if !environment.isEmpty {
                Divider()
                InfoRow(label: "Environment", value: environment.joined(separator: "\n"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func publishedPortsSection(_ details: ContainerCLI.ContainerDetails) -> some View {
        CollapsibleInfoCard(title: "Published Ports", systemImage: "arrow.left.arrow.right", isExpanded: $portsExpanded) {
            if details.configuration.publishedPorts.isEmpty {
                Text("No port mappings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(details.configuration.publishedPorts) { port in
                    InfoRow(label: "Port", value: portDisplay(port))
                    if port.id != details.configuration.publishedPorts.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func mountsSection(_ details: ContainerCLI.ContainerDetails) -> some View {
        CollapsibleInfoCard(title: "Mounts", systemImage: "externaldrive", isExpanded: $mountsExpanded) {
            if details.configuration.mounts.isEmpty {
                Text("No volume mounts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(details.configuration.mounts) { mount in
                    InfoRow(label: "Mount", value: "\(mount.source) → \(mount.destination)")
                    if let options = mount.options, !options.isEmpty {
                        InfoRow(label: "Options", value: options.joined(separator: ", "))
                    }
                    if mount.id != details.configuration.mounts.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func networksSection(_ details: ContainerCLI.ContainerDetails) -> some View {
        CollapsibleInfoCard(title: "Networks", systemImage: "network", isExpanded: $networksExpanded) {
            if details.configuration.networks.isEmpty {
                Text("Default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(details.configuration.networks) { network in
                    Text(network.network)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var restartPolicySection: some View {
        CollapsibleInfoCard(title: "Capsule Restart Policy", systemImage: "arrow.triangle.2.circlepath", isExpanded: $restartExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Automatically restart this container using Capsule's restart daemon")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Policy", selection: $restartPolicy) {
                    ForEach(RestartPolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .pickerStyle(.segmented)

                if restartPolicy != .no {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text("Restart daemon will monitor and restart this container")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func startContainer() {
        Task { await viewModel.startContainer(id: container.id) }
    }

    private func stopContainer() {
        Task { await viewModel.stopContainer(id: container.id) }
    }

    private func forceStopContainer() {
        Task { await viewModel.forceStopContainer(id: container.id) }
    }

    private func restartContainer() {
        Task {
            await viewModel.stopContainer(id: container.id)
            try? await Task.sleep(for: .seconds(1))
            await viewModel.startContainer(id: container.id)
        }
    }

    private func deleteContainer() {
        Task { await viewModel.deleteContainer(id: container.id) }
    }

    // MARK: - Restart Policy

    private func loadRestartPolicy() {
        if let data = UserDefaults.standard.data(forKey: "restartPolicy_\(container.id)"),
           let policy = try? JSONDecoder().decode(RestartPolicy.self, from: data) {
            restartPolicy = policy
        }
    }

    private func saveRestartPolicy(_ policy: RestartPolicy) {
        if let data = try? JSONEncoder().encode(policy) {
            UserDefaults.standard.set(data, forKey: "restartPolicy_\(container.id)")
        }
    }

    private func loadDetails() async {
        do {
            details = try await viewModel.runtime.inspectContainer(id: container.id)
            detailsError = nil
        } catch {
            details = nil
            detailsError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func commandDisplay(_ initProcess: ContainerCLI.ContainerDetails.Configuration.InitProcess) -> String {
        var parts: [String] = []
        if let executable = initProcess.executable, !executable.isEmpty {
            parts.append(executable)
        }
        parts.append(contentsOf: initProcess.arguments ?? [])
        return parts.isEmpty ? String(localized: "Image default") : parts.joined(separator: " ")
    }

    private func platformDisplay(_ platform: ContainerCLI.ContainerDetails.Configuration.Platform) -> String {
        [platform.os, platform.architecture, platform.variant]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "/")
    }

    private func portDisplay(_ port: ContainerCLI.ContainerDetails.Configuration.PublishedPort) -> String {
        let host = [
            port.hostAddress,
            port.hostPort.map(String.init),
        ]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ":")
        let container = "\(port.containerPort)/\(port.proto ?? "tcp")"
        return host.isEmpty ? container : "\(host) → \(container)"
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Logs View

struct ContainerLogsView: View {
    let container: ContainerSummary
    @ObservedObject var viewModel: ContainerViewModel

    @State private var logs: String = ""
    @State private var isLoading = false
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button(action: { Task { await refreshLogs() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)

                Spacer()

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Logs content
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if logs.isEmpty {
                            Text("No logs available")
                        } else {
                            Text(logs)
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id("bottom")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: logs) { _, _ in
                    if autoScroll {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .task {
            await refreshLogs()
        }
    }

    private func refreshLogs() async {
        isLoading = true
        do {
            logs = try await viewModel.runtime.getContainerLogs(id: container.id)
        } catch {
            let format = NSLocalizedString("Error loading logs: %@", comment: "Container logs loading error")
            logs = String(format: format, error.localizedDescription)
        }
        isLoading = false
    }
}

// MARK: - Terminal View

struct ContainerTerminalView: View {
    let container: ContainerSummary
    @ObservedObject var viewModel: ContainerViewModel

    @State private var output: String = ""
    @State private var input: String = ""
    @State private var isExecuting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                StatusBadge(status: container.status)

                if container.status != .running {
                    Text("Terminal is available when the container is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isExecuting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running command...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Clear") {
                    output = ""
                }
                .buttonStyle(.borderless)
                .disabled(output.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if output.isEmpty {
                            Text(terminalPlaceholder)
                        } else {
                            Text(output)
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id("terminal-bottom")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: output) { _, _ in
                    withAnimation {
                        proxy.scrollTo("terminal-bottom", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input area
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("Type a command...", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .disabled(container.status != .running || isExecuting)
                    .onSubmit {
                        executeCommand()
                    }

                if !input.isEmpty {
                    Button(action: executeCommand) {
                        Image(systemName: "return")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .disabled(container.status != .running || isExecuting)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var terminalPlaceholder: String {
        if container.status == .running {
            return "# Terminal ready. Type a command below.\n"
        }
        return "# Start the container to use the terminal.\n"
    }

    private func executeCommand() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard container.status == .running, !isExecuting else { return }

        let command = input
        output += "\n$ \(command)\n"
        input = ""
        isExecuting = true

        Task {
            do {
                let result = try await viewModel.runtime.executeInContainer(id: container.id, command: command)
                await MainActor.run {
                    output += result + "\n"
                    isExecuting = false
                }
            } catch {
                await MainActor.run {
                    let format = NSLocalizedString("Error: %@", comment: "Terminal command error")
                    output += String(format: format, error.localizedDescription) + "\n"
                    isExecuting = false
                }
            }
        }
    }
}

// MARK: - Files View

struct ContainerFilesView: View {
    let container: ContainerSummary
    @ObservedObject var viewModel: ContainerViewModel

    @State private var currentPath: String = "/"
    @State private var files: [ContainerCLI.FileInfo] = []
    @State private var selectedFileID: ContainerCLI.FileInfo.ID?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Path bar
            HStack(spacing: 8) {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(currentPath == "/")
                .help("Back")

                Text(currentPath)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()

                Button(action: openSelectedFolder) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(selectedFile?.isDirectory != true)
                .help("Open Folder")

                Button(role: .destructive, action: deleteSelectedFile) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(selectedFile == nil || selectedFile?.name == "..")
                .help("Delete")

                Button(action: { Task { await loadFiles() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(isLoading || container.status != .running)
                .help("Refresh")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // File list
            if container.status != .running {
                ContentUnavailableView {
                    Label("Files are available when the container is running", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Start the container to browse its filesystem.")
                }
            } else if isLoading && files.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Unable to Load Files", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await loadFiles() } }
                }
            } else {
                Table(files, selection: $selectedFileID) {
                    TableColumn("Name") { file in
                        HStack(spacing: 8) {
                            Image(systemName: fileIcon(file))
                                .foregroundStyle(file.isDirectory ? .blue : .secondary)
                                .frame(width: 16)
                            Text(file.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .width(min: 150, ideal: 300)

                    TableColumn("Date Modified") { file in
                        Text(file.modified)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 120, ideal: 160)

                    TableColumn("Size") { file in
                        Text(file.isDirectory ? "—" : formatSize(file.size))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 100)

                    TableColumn("Kind") { file in
                        Text(fileKind(file))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn("Owner") { file in
                        Text("\(file.owner):\(file.group)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 100, ideal: 130)

                    TableColumn("Permissions") { file in
                        Text(file.permissions)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 100, ideal: 120)
                }
            }
        }
        .task(id: container.id) {
            await loadFiles()
        }
    }

    private var selectedFile: ContainerCLI.FileInfo? {
        guard let selectedFileID else { return nil }
        return files.first { $0.id == selectedFileID }
    }

    private func goBack() {
        guard currentPath != "/" else { return }
        let components = currentPath.split(separator: "/").dropLast()
        currentPath = components.isEmpty ? "/" : "/" + components.joined(separator: "/")
        Task { await loadFiles() }
    }

    private func loadFiles() async {
        guard container.status == .running else {
            files = []
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            files = try await viewModel.runtime.listFiles(containerID: container.id, path: currentPath)
                .sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory {
                        return lhs.isDirectory && !rhs.isDirectory
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            selectedFileID = nil
        } catch {
            files = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func openSelectedFolder() {
        guard let selectedFile, selectedFile.isDirectory else { return }
        currentPath = selectedFile.path
        Task { await loadFiles() }
    }

    private func deleteSelectedFile() {
        guard let selectedFile else { return }
        Task {
            do {
                try await viewModel.runtime.deleteFile(containerID: container.id, path: selectedFile.path)
                await loadFiles()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func fileIcon(_ file: ContainerCLI.FileInfo) -> String {
        if file.isDirectory { return "folder.fill" }
        if file.isSymlink { return "link" }
        return "doc"
    }

    private func fileKind(_ file: ContainerCLI.FileInfo) -> String {
        if file.isDirectory { return String(localized: "Folder") }
        if file.isSymlink { return String(localized: "Symbolic Link") }
        return String(localized: "File")
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
