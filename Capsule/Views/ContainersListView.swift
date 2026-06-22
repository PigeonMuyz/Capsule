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
            listHeader

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
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $showingAddSheet) {
            AddContainerView(viewModel: viewModel, composeManager: composeManager)
        }
    }

    private var listHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Containers")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(statusSubtitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            .help("Add container, import, or compose")
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.top, 42)
        .padding(.bottom, 14)
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

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case "info":
            InfoTabView(container: container, runtime: viewModel.runtime)
        case "logs":
            LogsTabView(container: container, viewModel: viewModel)
        case "terminal":
            TerminalTabView(container: container)
        case "files":
            FilesTabView(container: container, runtime: viewModel.runtime)
        default:
            EmptyView()
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
    let runtime: RuntimeCore
    @State private var details: ContainerCLI.ContainerDetails?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
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

                if isLoading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading inspect data...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    InfoSection(title: "Inspect") {
                        InfoRow(label: "Error", value: errorMessage)
                    }
                }

                if let details {
                    inspectSections(details)
                }

                Spacer(minLength: 16)
            }
            .padding()
        }
        .task(id: container.id) {
            await loadDetails()
        }
    }

    @ViewBuilder
    private func inspectSections(_ details: ContainerCLI.ContainerDetails) -> some View {
        InfoSection(title: "Command") {
            InfoRow(label: "Executable", value: details.configuration.initProcess?.executable ?? "--")
            let arguments = details.configuration.initProcess?.arguments?.joined(separator: " ") ?? ""
            InfoRow(label: "Arguments", value: arguments.isEmpty ? "--" : arguments)
            InfoRow(label: "Workdir", value: details.configuration.initProcess?.workingDirectory ?? "--")
        }

        InfoSection(title: "Mounts") {
            let mounts = details.configuration.mounts
            if mounts.isEmpty {
                InfoRow(label: "Mounts", value: "None")
            } else {
                ForEach(mounts) { mount in
                    InfoTwoColumnRow(
                        leadingLabel: mount.source.isEmpty ? "(runtime)" : mount.source,
                        trailingLabel: mount.destination
                    )
                }
            }
        }

        InfoSection(title: "Ports") {
            let ports = details.configuration.publishedPorts
            if ports.isEmpty {
                InfoRow(label: "Ports", value: "None")
            } else {
                ForEach(ports) { port in
                    let proto = port.proto ?? "tcp"
                    let host = port.hostAddress ?? "0.0.0.0"
                    let hostPort = port.hostPort.map(String.init) ?? "-"
                    InfoTwoColumnRow(
                        leadingLabel: "\(host):\(hostPort)",
                        trailingLabel: "\(port.containerPort)/\(proto)"
                    )
                }
            }
        }

        InfoSection(title: "Environment") {
            let environment = details.configuration.initProcess?.environment ?? []
            if environment.isEmpty {
                InfoRow(label: "Environment", value: "None")
            } else {
                ForEach(environment, id: \.self) { item in
                    let pair = splitEnvironment(item)
                    InfoRow(label: LocalizedStringKey(pair.key), value: pair.value)
                }
            }
        }
    }

    private func loadDetails() async {
        isLoading = true
        errorMessage = nil
        do {
            details = try await runtime.inspectContainer(id: container.id)
        } catch is CancellationError {
            return
        } catch {
            details = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func splitEnvironment(_ value: String) -> (key: String, value: String) {
        guard let index = value.firstIndex(of: "=") else {
            return (value, "")
        }
        return (String(value[..<index]), String(value[value.index(after: index)...]))
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

struct InfoTwoColumnRow: View {
    let leadingLabel: String
    let trailingLabel: String

    var body: some View {
        HStack(spacing: 16) {
            Text(leadingLabel)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 16)

            Text(trailingLabel)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Logs Tab

struct LogsTabView: View {
    let container: ContainerSummary
    @ObservedObject var viewModel: ContainerViewModel
    @State private var logs: [LogCacheStore.Entry] = []
    @State private var retention = LogRetentionPolicy.defaultPolicy
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(logs.count) cached lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings) {
                    logSettings
                        .padding()
                        .frame(width: 260)
                }

                Button {
                    clearLogs()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Clear cached logs")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if logs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No cached logs yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(logs) { entry in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(formatTimestamp(entry.timestamp))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 76, alignment: .leading)

                                    Text(entry.content)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                                .id(entry.id)
                            }
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: logs.count) { _, _ in
                        if let last = logs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .task(id: container.id) {
            await loadLogs()
        }
    }

    private var logSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Log Retention")
                .font(.headline)

            Stepper("Days: \(retention.days)", value: $retention.days, in: 1...90)
            Stepper("Max lines: \(retention.maxEntries)", value: $retention.maxEntries, in: 100...50_000, step: 100)

            Button("Apply") {
                retention.save(containerID: container.id)
                showSettings = false
                Task { await reloadCache() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func loadLogs() async {
        retention = LogRetentionPolicy.load(containerID: container.id)
        await reloadCache()

        if logs.isEmpty, let text = try? await viewModel.runtime.getContainerLogs(id: container.id, tail: retention.maxEntries) {
            for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) where !line.isEmpty {
                await appendLog(line)
            }
        }

        guard container.status == .running else { return }
        do {
            for try await line in viewModel.runtime.streamContainerLogs(id: container.id) {
                await appendLog(line)
            }
        } catch {
            // Stream ended or container stopped.
        }
    }

    private func appendLog(_ line: String) async {
        let entry = LogCacheStore.Entry(content: line)
        await LogCacheStore.shared.append(entry, for: container.id, retention: retention)
        logs.append(entry)
        if logs.count > retention.maxEntries {
            logs.removeFirst(logs.count - retention.maxEntries)
        }
    }

    private func reloadCache() async {
        logs = await LogCacheStore.shared.entries(for: container.id, retention: retention)
    }

    private func clearLogs() {
        Task {
            await LogCacheStore.shared.clear(containerID: container.id)
            logs = []
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let runtime: RuntimeCore

    var body: some View {
        ContainerFilesView(containerID: container.id, containerName: container.name, runtime: runtime)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
