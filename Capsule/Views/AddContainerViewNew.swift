import SwiftUI
import AppKit

/// Redesigned "Add Container" sheet with simplified TabView
struct AddContainerViewNew: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ContainerViewModel
    @ObservedObject var composeManager: ComposeManager

    @State private var selectedTab = 0

    // Single container fields
    @State private var image = ""
    @State private var name = ""
    @State private var ports: [PortMapping] = []
    @State private var volumes: [VolumeMapping] = []
    @State private var environment: [EnvVar] = []

    // Compose fields
    @State private var projectName = ""
    @State private var composeYAML = ""

    @State private var isWorking = false
    @State private var errorMessage: String?

    struct PortMapping: Identifiable {
        let id = UUID()
        var host = ""
        var container = ""
    }

    struct VolumeMapping: Identifiable {
        let id = UUID()
        var host = ""
        var container = ""
    }

    struct EnvVar: Identifiable {
        let id = UUID()
        var key = ""
        var value = ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title
            HStack {
                Text("New Container")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // Tab selector using Picker
            HStack {
                Spacer()
                Picker("", selection: $selectedTab) {
                    Text("Create Container").tag(0)
                    Text("Docker Compose").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)
                Spacer()
            }
            .padding(.vertical, 12)

            Divider()

            // Tab content
            Group {
                if selectedTab == 0 {
                    createContainerTab
                } else {
                    dockerComposeTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Error message
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding()
                .background(Color.red.opacity(0.08))
            }

            Divider()

            // Bottom buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    createContainer(startImmediately: false)
                }
                .disabled(isCreateDisabled)

                Button("Create & Start") {
                    createContainer(startImmediately: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreateDisabled)
            }
            .padding()
        }
        .frame(width: 800, height: 600)
    }

    // MARK: - Create Container Tab

    private var createContainerTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Image section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Image")
                        .font(.headline)

                    TextField("docker.io/library/nginx:latest", text: $image)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    TextField("Container name (optional)", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                // Ports section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Ports")
                            .font(.headline)
                        Spacer()
                        Button {
                            ports.append(PortMapping())
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                    }

                    if ports.isEmpty {
                        Text("No port mappings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($ports) { $port in
                            HStack(spacing: 8) {
                                TextField("8080", text: $port.host)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.secondary)
                                TextField("80", text: $port.container)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)

                                Spacer()

                                Button {
                                    ports.removeAll { $0.id == port.id }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Divider()

                // Volumes section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Volumes")
                            .font(.headline)
                        Spacer()
                        Button {
                            volumes.append(VolumeMapping())
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                    }

                    if volumes.isEmpty {
                        Text("No volume mounts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($volumes) { $volume in
                            VStack(spacing: 8) {
                                HStack {
                                    TextField("Host path", text: $volume.host)
                                        .textFieldStyle(.roundedBorder)

                                    Button {
                                        if let path = chooseDirectory() {
                                            volume.host = path
                                        }
                                    } label: {
                                        Image(systemName: "folder")
                                    }
                                    .buttonStyle(.borderless)

                                    Button {
                                        volumes.removeAll { $0.id == volume.id }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }

                                HStack {
                                    Image(systemName: "arrow.down")
                                        .foregroundStyle(.secondary)
                                    TextField("Container path", text: $volume.container)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }
                }

                Divider()

                // Environment section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Environment")
                            .font(.headline)
                        Spacer()
                        Button {
                            environment.append(EnvVar())
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                    }

                    if environment.isEmpty {
                        Text("No environment variables")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($environment) { $env in
                            HStack(spacing: 8) {
                                TextField("KEY", text: $env.key)
                                    .textFieldStyle(.roundedBorder)
                                Text("=")
                                    .foregroundStyle(.secondary)
                                TextField("value", text: $env.value)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    environment.removeAll { $0.id == env.id }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Docker Compose Tab

    private var dockerComposeTab: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                // Project name
                HStack {
                    Text("Project Name")
                        .font(.headline)
                    Spacer()
                    TextField("my-app", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }

                // YAML editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("docker-compose.yml")
                        .font(.headline)

                    TextEditor(text: $composeYAML)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 300)
                        .border(Color.secondary.opacity(0.3))
                        .cornerRadius(6)
                }

                // Load example button
                HStack {
                    Button("Load Example") {
                        loadExampleCompose()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text("Paste your docker-compose.yml content above")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)

            Spacer()
        }
    }

    // MARK: - Helper Functions

    private var isCreateDisabled: Bool {
        if selectedTab == 0 {
            // Create Container tab
            return image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            // Docker Compose tab
            return projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   composeYAML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func createContainer(startImmediately: Bool) {
        errorMessage = nil
        isWorking = true

        Task {
            do {
                if selectedTab == 0 {
                    // Create single container
                    try await createSingleContainer(startImmediately: startImmediately)
                } else {
                    // Create compose project
                    try await createComposeProject()
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

    private func createSingleContainer(startImmediately: Bool) async throws {
        let trimmedImage = image.trimmingCharacters(in: .whitespacesAndNewlines)
        let containerName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? suggestedName(from: trimmedImage)
            : name.trimmingCharacters(in: .whitespacesAndNewlines)

        var spec = ContainerSpec(
            name: containerName,
            image: trimmedImage,
            cpus: 2,
            memoryBytes: 2 * 1024 * 1024 * 1024,
            command: [],
            workingDirectory: "/"
        )

        // Add ports
        spec.publishedPorts = ports.compactMap { port in
            let h = port.host.trimmingCharacters(in: .whitespacesAndNewlines)
            let c = port.container.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !h.isEmpty, !c.isEmpty else { return nil }
            return "\(h):\(c)"
        }

        // Add volumes
        spec.volumeBinds = volumes.compactMap { volume in
            let h = volume.host.trimmingCharacters(in: .whitespacesAndNewlines)
            let c = volume.container.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !h.isEmpty, !c.isEmpty else { return nil }
            return "\(h):\(c)"
        }

        // Add environment
        spec.environment = Dictionary(
            environment.compactMap { env in
                let k = env.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let v = env.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !k.isEmpty else { return nil }
                return (k, v)
            },
            uniquingKeysWith: { _, last in last }
        )

        if startImmediately {
            let summary = try await viewModel.runtime.createContainer(spec)
            try await viewModel.runtime.startContainer(id: summary.id)
            await viewModel.refresh()
        } else {
            await viewModel.createContainer(spec: spec)
        }
    }

    private func createComposeProject() async throws {
        let trimmedProject = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = try DockerComposeParser.parse(yamlContent: composeYAML, appName: trimmedProject)

        _ = try await composeManager.createProject(
            name: parsed.name,
            services: parsed.services,
            volumes: parsed.volumes,
            networks: parsed.networks
        )
    }

    private func suggestedName(from image: String) -> String {
        let base = image
            .split(separator: "/").last?
            .split(separator: ":").first
            .map(String.init) ?? "my-container"
        return base.isEmpty ? "my-container" : base.replacingOccurrences(of: ".", with: "-")
    }

    private func loadExampleCompose() {
        composeYAML = """
version: '3'
services:
  web:
    image: nginx:latest
    ports:
      - "8080:80"
  db:
    image: postgres:14
    environment:
      POSTGRES_PASSWORD: example
"""
        projectName = "example-app"
    }

    private func chooseDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

#Preview {
    let vm = ContainerViewModel()
    AddContainerViewNew(viewModel: vm, composeManager: ComposeManager(runtime: vm.runtime))
}
