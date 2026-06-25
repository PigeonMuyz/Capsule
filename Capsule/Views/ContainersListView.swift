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
        VStack(spacing: 0) {
            if viewModel.containers.isEmpty && composeManager.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        // Running containers section
                        let runningContainers = standaloneContainers.filter { $0.status == .running || $0.status == .starting }
                        if !runningContainers.isEmpty {
                            Section {
                                ForEach(runningContainers) { container in
                                    containerRow(container)
                                }
                            } header: {
                                sectionHeader("Running")
                            }
                        }

                        // Compose projects section
                        if !composeManager.projects.isEmpty {
                            Section {
                                ForEach(composeManager.projects) { project in
                                    projectGroup(project)
                                }
                            } header: {
                                sectionHeader("Projects")
                            }
                        }

                        // Stopped containers section
                        let stoppedContainers = standaloneContainers.filter { $0.status != .running && $0.status != .starting }
                        if !stoppedContainers.isEmpty {
                            Section {
                                ForEach(stoppedContainers) { container in
                                    containerRow(container)
                                }
                            } header: {
                                sectionHeader("Stopped")
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
            AddContainerView(viewModel: viewModel, composeManager: composeManager)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Color(nsColor: .controlBackgroundColor))
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

        VStack(spacing: 0) {
            Button(action: { selection = .project(project.id) }) {
                HStack(spacing: 10) {
                    Button(action: { toggleExpanded(project.id) }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.indigo)

                    Text(project.name)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(project.services.count) services")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Circle()
                        .fill(projectStatusColor(project.status))
                        .frame(width: 8, height: 8)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
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
                VStack(spacing: 4) {
                    ForEach(projectContainers(project)) { container in
                        containerRow(container, indented: true)
                    }
                }
                .padding(.top, 4)
            }
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

// MARK: - Container Card (OrbStack-style)

struct ContainerCard: View {
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
                // 状态指示灯
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(container.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    HStack(spacing: 6) {
                        Text(simplifiedImageName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let badge = registryBadge {
                            Text(badge)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(badgeColor.opacity(0.15))
                                .foregroundStyle(badgeColor)
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()
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

    private var registryBadge: String? {
        ImageDisplayHelper.getRegistryBadge(container.image)
    }

    private var badgeColor: Color {
        ImageDisplayHelper.getBadgeColor(container.image)
    }

    private var statusColor: Color {
        switch container.status {
        case .running: return .green
        case .starting: return .orange
        case .failed: return .red
        default: return .gray
        }
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
        case .starting: return .orange
        case .stopped, .created: return .gray
        case .failed: return .red
        default: return .secondary
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
        .navigationTitle(container?.name ?? "Container")
        .navigationSubtitle(container?.image ?? "")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Apple Container CLI Native: Basic Controls
                InfoSection(title: "Controls") {
                    HStack(spacing: 12) {
                        if container.status == .running {
                            Button(action: stopContainer) {
                                Label("Stop", systemImage: "stop.fill")
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

                        Spacer()

                        Button(role: .destructive, action: deleteContainer) {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Apple Container CLI Native: General Info
                InfoSection(title: "General") {
                    InfoRow(label: "Name", value: container.name)
                    Divider()
                    InfoRow(label: "ID", value: String(container.id.prefix(12)))
                    Divider()
                    InfoRow(label: "Image", value: container.image)
                    Divider()
                    InfoRow(label: "Status", value: container.status.displayName)
                }

                // Apple Container CLI Native: Resources
                InfoSection(title: "Resources") {
                    InfoRow(label: "CPUs", value: "\(container.cpus)")
                    Divider()
                    InfoRow(label: "Memory", value: formatMemory(container.memoryBytes))
                }

                // Apple Container CLI Native: Timestamps
                InfoSection(title: "Timestamps") {
                    InfoRow(label: "Created", value: formatDate(container.createdAt))
                    if let started = container.startedAt {
                        Divider()
                        InfoRow(label: "Started", value: formatDate(started))
                    }
                }

                // 🔸 Capsule Enhancement: Restart Policy (Software Daemon)
                InfoSection(title: "🔸 Capsule: Restart Policy") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Automatically restart this container using Capsule's restart daemon")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Policy", selection: $restartPolicy) {
                            Text("No").tag(RestartPolicy.no)
                            Text("Always").tag(RestartPolicy.always)
                            Text("On Failure").tag(RestartPolicy.onFailure)
                            Text("Unless Stopped").tag(RestartPolicy.unlessStopped)
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
                .task {
                    loadRestartPolicy()
                }
                .onChange(of: restartPolicy) { _, newValue in
                    saveRestartPolicy(newValue)
                }

                Spacer(minLength: 16)
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Actions

    private func startContainer() {
        Task { await viewModel.startContainer(id: container.id) }
    }

    private func stopContainer() {
        Task { await viewModel.stopContainer(id: container.id) }
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

    // MARK: - Helpers

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
                    Text(logs.isEmpty ? "No logs available" : logs)
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
            logs = "Error loading logs: \(error.localizedDescription)"
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

    var body: some View {
        VStack(spacing: 0) {
            // Output area
            ScrollView {
                Text(output.isEmpty ? "# Terminal ready. Type a command below.\n" : output)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            // Input area
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("Type a command...", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
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
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func executeCommand() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let command = input
        output += "\n$ \(command)\n"
        input = ""

        Task {
            do {
                let result = try await viewModel.runtime.executeInContainer(id: container.id, command: command)
                await MainActor.run {
                    output += result + "\n"
                }
            } catch {
                await MainActor.run {
                    output += "Error: \(error.localizedDescription)\n"
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
    @State private var files: [FileItem] = []
    @State private var isLoading = false

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

                Text(currentPath)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button(action: { Task { await loadFiles() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // File list
            if isLoading && files.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(files) {
                    TableColumn("Name") { file in
                        HStack(spacing: 8) {
                            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                                .foregroundStyle(file.isDirectory ? .blue : .secondary)
                            Text(file.name)
                                .font(.system(size: 13))
                        }
                    }
                    .width(min: 150, ideal: 300)

                    TableColumn("Size") { file in
                        Text(file.size)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 100)

                    TableColumn("Kind") { file in
                        Text(file.kind)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 120)
                }
            }
        }
        .task {
            await loadFiles()
        }
    }

    private func goBack() {
        guard currentPath != "/" else { return }
        let components = currentPath.split(separator: "/").dropLast()
        currentPath = components.isEmpty ? "/" : "/" + components.joined(separator: "/")
        Task { await loadFiles() }
    }

    private func loadFiles() async {
        isLoading = true
        do {
            let command = "ls -lAh --time-style=long-iso \(currentPath)"
            let output = try await viewModel.runtime.executeInContainer(id: container.id, command: command)
            files = parseFileList(output)
        } catch {
            files = []
        }
        isLoading = false
    }

    private func parseFileList(_ output: String) -> [FileItem] {
        var items: [FileItem] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }

            let permissions = String(parts[0])
            let isDirectory = permissions.hasPrefix("d")
            let size = String(parts[4])
            let name = parts[8...].joined(separator: " ")

            items.append(FileItem(
                name: name,
                isDirectory: isDirectory,
                size: size,
                kind: isDirectory ? "Folder" : "File"
            ))
        }
        return items
    }
}

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
    let size: String
    let kind: String
}

