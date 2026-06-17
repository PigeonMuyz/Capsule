import SwiftUI

/// View for displaying container logs
struct ContainerLogsView: View {
    let containerID: String
    let containerName: String
    @ObservedObject var viewModel: ContainerViewModel

    @State private var logs: [LogLine] = []
    @State private var autoScroll = true
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Logs: \(containerName)")
                    .font(.headline)

                Spacer()

                Toggle(isOn: $autoScroll) {
                    Label("Auto-scroll", systemImage: "arrow.down.to.line")
                }
                .toggleStyle(.button)

                Button(action: clearLogs) {
                    Label("Clear", systemImage: "trash")
                }
                .help("Clear logs")
            }
            .padding()

            Divider()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Logs content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredLogs) { log in
                            logLineView(log)
                                .id(log.id)
                        }
                    }
                }
                .onChange(of: logs.count) { _, _ in
                    if autoScroll, let lastLog = logs.last {
                        withAnimation {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .task {
            await loadLogs()
        }
        .onDisappear {
            // Stop streaming when view disappears
        }
    }

    private var filteredLogs: [LogLine] {
        if searchText.isEmpty {
            return logs
        }
        return logs.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    private func logLineView(_ log: LogLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(formatTimestamp(log.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            // Stream indicator
            Circle()
                .fill(log.stream == .stdout ? Color.blue : Color.orange)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            // Content
            Text(log.content)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(log.stream == .stderr ? .red : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            searchText.isEmpty ? Color.clear :
                log.content.localizedCaseInsensitiveContains(searchText) ?
                Color.yellow.opacity(0.2) : Color.clear
        )
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func loadLogs() async {
        // Load existing logs
        logs = await viewModel.getLogs(containerID: containerID)

        // Start streaming new logs
        await streamLogs()
    }

    private func streamLogs() async {
        for await log in await viewModel.streamLogs(containerID: containerID) {
            logs.append(log)
        }
    }

    private func clearLogs() {
        Task {
            await viewModel.clearLogs(containerID: containerID)
            logs.removeAll()
        }
    }
}

/// Container detail view with multiple tabs
struct ContainerDetailView: View {
    let container: ContainerSummary
    @ObservedObject var viewModel: ContainerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Container header with actions
                containerHeader

                Divider()

                // Tab picker
                Picker("View", selection: $selectedTab) {
                    Text("Info").tag(0)
                    Text("Logs").tag(1)
                    Text("Terminal").tag(2)
                    Text("Files").tag(3)
                    Text("Stats").tag(4)
                }
                .pickerStyle(.segmented)
                .padding()

                // Tab content
                TabView(selection: $selectedTab) {
                    overviewTab
                        .tag(0)

                    ContainerLogsView(
                        containerID: container.id,
                        containerName: container.name,
                        viewModel: viewModel
                    )
                    .tag(1)

                    ContainerTerminalView(
                        containerID: container.id,
                        containerName: container.name
                    )
                    .tag(2)

                    ContainerFilesView(
                        containerID: container.id,
                        containerName: container.name
                    )
                    .tag(3)

                    ContainerStatsView(
                        containerID: container.id,
                        containerName: container.name
                    )
                    .tag(4)
                }
                .tabViewStyle(.automatic)
            }
            .navigationTitle("Container Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .frame(width: 800, height: 600)
        }
    }

    // MARK: - Container Header

    private var containerHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(container.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Quick actions
            HStack(spacing: 8) {
                if container.status.canStart {
                    Button(action: {
                        Task {
                            await viewModel.startContainer(id: container.id)
                        }
                    }) {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }

                if container.status.canStop {
                    Button(action: {
                        Task {
                            await viewModel.stopContainer(id: container.id)
                        }
                    }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Menu {
                    Button(action: {
                        Task {
                            await viewModel.deleteContainer(id: container.id)
                            dismiss()
                        }
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(container.status.isActive)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
            }

            statusBadge(for: container.status)
        }
        .padding()
    }

    private var overviewTab: some View {
        Form {
            Section("General") {
                LabeledContent("ID", value: container.id)
                    .font(.system(.body, design: .monospaced))
                LabeledContent("Name", value: container.name)
                LabeledContent("Image", value: container.image)
                LabeledContent("Status", value: container.status.displayName)
            }

            Section("Resources") {
                LabeledContent("CPUs", value: "\(container.cpus)")
                LabeledContent("Memory", value: container.memoryDisplayString)
            }

            Section("Timeline") {
                LabeledContent("Created", value: formatDate(container.createdAt))
                if let startedAt = container.startedAt {
                    LabeledContent("Started", value: formatDate(startedAt))
                }
                if let stoppedAt = container.stoppedAt {
                    LabeledContent("Stopped", value: formatDate(stoppedAt))
                }
                if let uptime = container.uptimeString {
                    LabeledContent("Uptime", value: uptime)
                }
            }

            if let error = container.lastError {
                Section("Error") {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func statusBadge(for status: ContainerStatus) -> some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview("Logs") {
    ContainerLogsView(
        containerID: "test-1",
        containerName: "test-container",
        viewModel: ContainerViewModel()
    )
    .frame(width: 700, height: 400)
}

#Preview("Detail") {
    ContainerDetailView(
        container: ContainerSummary(
            id: "test-1",
            name: "test-container",
            image: "alpine:latest",
            status: .running,
            cpus: 2,
            memoryBytes: 2 * 1024 * 1024 * 1024,
            createdAt: Date(),
            startedAt: Date()
        ),
        viewModel: ContainerViewModel()
    )
}
