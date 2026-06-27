import SwiftUI

/// Detail panel for a compose project, shown in the right column of the
/// Containers view when a project group is selected. Embeddable (no sheet
/// chrome) — mirrors `ContainerDetailPanel`.
struct ProjectDetailPanel: View {
    let project: ComposeManager.ComposeProjectInfo
    @ObservedObject var composeManager: ComposeManager
    @State private var logs: [(service: String, line: String)] = []
    @State private var selectedTab: DetailTab = .info
    @State private var showingRemoveSheet = false

    enum DetailTab: String, CaseIterable, Identifiable {
        case info = "Info"
        case services = "Services"
        case logs = "Logs"

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .info: return "Info"
            case .services: return "Services"
            case .logs: return "Logs"
            }
        }
    }

    var body: some View {
        Group {
            switch selectedTab {
            case .info:
                ProjectInfoView(project: project, composeManager: composeManager)
            case .services:
                ProjectServicesView(project: project)
            case .logs:
                ProjectLogsView(logs: logs)
            }
        }
        .navigationTitle(project.name)
        .navigationSubtitle(String.localizedStringWithFormat(NSLocalizedString("%lld services", comment: "Number of compose services"), project.serviceCount))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }

            ToolbarItem(placement: .primaryAction) {
                projectAction
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if project.status == .running || project.status == .partial {
                        Button("Force Stop", role: .destructive) {
                            Task { try? await composeManager.forceStopProject(id: project.id) }
                        }
                        Divider()
                    }
                    Button("Remove...", role: .destructive) {
                        showingRemoveSheet = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .task(id: project.id) {
            await streamLogs()
        }
        .sheet(isPresented: $showingRemoveSheet) {
            RemoveComposeProjectView(project: project, composeManager: composeManager)
        }
    }

    @ViewBuilder
    private var projectAction: some View {
        if project.status == .creating {
            ProgressView()
                .controlSize(.small)
        } else if project.status == .running || project.status == .partial {
            Button(action: { Task { try? await composeManager.stopProject(id: project.id) } }) {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
        } else {
            Button(action: { Task { try? await composeManager.startProject(id: project.id) } }) {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func streamLogs() async {
        logs = []
        do {
            let stream = try await composeManager.getProjectLogs(id: project.id)
            for await log in stream {
                logs.append(log)
                if logs.count > 100 { logs.removeFirst() }
            }
        } catch {
            print("Failed to stream logs: \(error)")
        }
    }
}

private struct ProjectInfoView: View {
    let project: ComposeManager.ComposeProjectInfo
    @ObservedObject var composeManager: ComposeManager
    @State private var showingRemoveSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overviewHeader
                controlsBar
                InfoSection(title: "General") {
                    InfoRow(label: "Name", value: project.name)
                    Divider()
                    InfoRow(label: "Status", value: project.status.displayName)
                    Divider()
                    InfoRow(label: "Services", value: "\(project.serviceCount)")
                }
                servicesSummary
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingRemoveSheet) {
            RemoveComposeProjectView(project: project, composeManager: composeManager)
        }
    }

    private var overviewHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.indigo.opacity(0.16))
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.title2)
                    .foregroundStyle(.indigo)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(String.localizedStringWithFormat(NSLocalizedString("%lld services", comment: "Number of compose services"), project.serviceCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            ComposeProjectStatusBadge(status: project.status)
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

            if project.status == .creating {
                ProgressView()
                    .controlSize(.small)
            } else if project.status == .running || project.status == .partial {
                Button(action: { Task { try? await composeManager.stopProject(id: project.id) } }) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: { Task { try? await composeManager.forceStopProject(id: project.id) } }) {
                    Label("Force Stop", systemImage: "xmark.octagon.fill")
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: { Task { try? await composeManager.startProject(id: project.id) } }) {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Menu {
                if project.status == .running || project.status == .partial {
                    Button("Force Stop", role: .destructive) {
                        Task { try? await composeManager.forceStopProject(id: project.id) }
                    }
                    Divider()
                }
                Button("Remove...", role: .destructive) {
                    showingRemoveSheet = true
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .menuStyle(.button)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var servicesSummary: some View {
        InfoSection(title: "Services") {
            ForEach(project.services) { service in
                ServiceSummaryRow(service: service)
                if service.id != project.services.last?.id {
                    Divider()
                }
            }
        }
    }
}

struct RemoveComposeProjectView: View {
    @Environment(\.dismiss) private var dismiss
    let project: ComposeManager.ComposeProjectInfo
    @ObservedObject var composeManager: ComposeManager
    var onRemoved: () -> Void = {}

    @State private var deleteCreatedNetworks = true
    @State private var deleteCreatedVolumes = true
    @State private var deleteImages = false
    @State private var isRemoving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Compose") {
                    InfoRow(label: "Name", value: project.name)
                    Divider()
                    InfoRow(label: "Services", value: "\(project.serviceCount)")
                }

                Section("Resources") {
                    cleanupToggle(
                        title: "Delete created networks",
                        systemImage: "network",
                        names: project.createdNetworks,
                        isOn: $deleteCreatedNetworks
                    )

                    cleanupToggle(
                        title: "Delete created volumes",
                        systemImage: "externaldrive",
                        names: project.createdVolumes,
                        isOn: $deleteCreatedVolumes
                    )

                    cleanupToggle(
                        title: "Delete images",
                        systemImage: "photo.stack",
                        names: project.imageReferences,
                        isOn: $deleteImages
                    )
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if isRemoving {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Removing...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Remove Compose Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isRemoving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Remove", role: .destructive) {
                        removeProject()
                    }
                    .disabled(isRemoving)
                }
            }
            .frame(width: 560, height: 460)
        }
    }

    private func cleanupToggle(
        title: LocalizedStringKey,
        systemImage: String,
        names: [String],
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                    Text(resourceSummary(names))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .disabled(names.isEmpty || isRemoving)
    }

    private func resourceSummary(_ names: [String]) -> String {
        names.isEmpty ? String(localized: "None") : names.joined(separator: ", ")
    }

    private func removeProject() {
        isRemoving = true
        errorMessage = nil

        let options = ComposeRemovalOptions(
            deleteCreatedNetworks: deleteCreatedNetworks,
            deleteCreatedVolumes: deleteCreatedVolumes,
            deleteImages: deleteImages
        )

        Task { @MainActor in
            do {
                try await composeManager.removeProject(id: project.id, options: options)
                onRemoved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isRemoving = false
            }
        }
    }
}

private struct ProjectServicesView: View {
    let project: ComposeManager.ComposeProjectInfo

    var body: some View {
        ScrollView {
            InfoSection(title: "Services") {
                ForEach(project.services) { service in
                    ServiceSummaryRow(service: service)
                    if service.id != project.services.last?.id {
                        Divider()
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ProjectLogsView: View {
    let logs: [(service: String, line: String)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if logs.isEmpty {
                    Text("No logs yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(logs.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            Text("[\(logs[index].service)]")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(logs[index].line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ServiceSummaryRow: View {
    let service: ComposeManager.ComposeProjectInfo.ServiceInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cube.fill")
                .foregroundStyle(.blue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.containerName)
                    .font(.system(.subheadline, design: .monospaced))
                    .textSelection(.enabled)
                Text(service.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

private struct ComposeProjectStatusBadge: View {
    let status: ComposeManager.ComposeProjectInfo.ProjectStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension ComposeManager.ComposeProjectInfo.ProjectStatus {
    var displayName: String {
        switch self {
        case .creating: return NSLocalizedString("status.creating", value: "Creating", comment: "Project status")
        case .running: return NSLocalizedString("status.running", value: "Running", comment: "Project status")
        case .stopped: return NSLocalizedString("status.stopped", value: "Stopped", comment: "Project status")
        case .partial: return String(localized: "Partial")
        case .error: return String(localized: "Error")
        }
    }

    var color: Color {
        switch self {
        case .creating, .partial: return .orange
        case .running: return .green
        case .stopped: return .gray
        case .error: return .red
        }
    }
}
