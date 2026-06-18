import SwiftUI
import AppKit

/// Unified "Add" sheet for containers: a single entry point that merges the
/// form-based creation and the Docker import flows into one segmented sheet.
///
/// Modes:
///   - Configure:  fill in image / resources / env / ports / network
///   - Docker Run: paste a `docker run …` command
///   - Compose:    paste a docker-compose.yml + project name
struct AddContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ContainerViewModel
    @ObservedObject var composeManager: ComposeManager

    enum Mode: Int, CaseIterable, Identifiable {
        case configure, dockerRun, compose
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .configure: return NSLocalizedString("Configure", comment: "")
            case .dockerRun: return NSLocalizedString("Docker Run", comment: "")
            case .compose: return NSLocalizedString("Compose", comment: "")
            }
        }
    }

    /// One environment variable row.
    struct EnvVar: Identifiable { let id = UUID(); var key = ""; var value = "" }
    /// One published-port row (host → container).
    struct PortPair: Identifiable { let id = UUID(); var host = ""; var container = "" }
    /// One volume bind row (host path → container path).
    struct MountBind: Identifiable { let id = UUID(); var host = ""; var container = "" }

    static let platforms = ["auto", "linux/arm64", "linux/amd64"]

    @State private var mode: Mode = .configure

    // Configure fields
    @State private var name = ""
    @State private var image = ""
    @State private var platform = "auto"
    @State private var cpus: Double = 2
    @State private var memoryGB = 2.0
    @State private var command = ""          // empty → use the image's default
    @State private var workingDirectory = ""
    @State private var envVars: [EnvVar] = []
    @State private var ports: [PortPair] = []
    @State private var mounts: [MountBind] = []
    @State private var networkChoice = ""    // empty → default network
    @State private var availableNetworks: [ContainerCLI.NetworkInfo] = []

    // Docker Run field
    @State private var dockerCommand = ""

    // Compose fields
    @State private var projectName = ""
    @State private var composeContent = ""

    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()

                Divider()

                Group {
                    switch mode {
                    case .configure: configureForm
                    case .dockerRun:  dockerRunForm
                    case .compose:    composeForm
                    }
                }
                .frame(maxHeight: .infinity)

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
            }
            .navigationTitle("Add Container")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { submit() }
                        .disabled(isSubmitDisabled || isWorking)
                }
            }
            .frame(width: 640, height: 600)
        }
    }

    // MARK: - Configure

    private var configureForm: some View {
        Form {
            Section("Container Information") {
                TextField("Name", text: $name, prompt: Text("my-container"))
                    .textFieldStyle(.roundedBorder)

                TextField("Image", text: $image, prompt: Text("e.g. nginx:latest"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Picker("Platform", selection: $platform) {
                    ForEach(Self.platforms, id: \.self) { Text($0).tag($0) }
                }
            }

            Section("Resources") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPUs")
                    ResourceField(value: $cpus, range: 1...8, step: 1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory")
                    ResourceField(value: $memoryGB, range: 0.5...16, step: 0.5, unit: "GB")
                }
            }

            Section("Command") {
                TextField("Command", text: $command, prompt: Text("Leave empty to use the image default"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                TextField("Working Directory", text: $workingDirectory, prompt: Text("/"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            Section {
                ForEach($mounts) { $mount in
                    VStack(spacing: 6) {
                        HStack {
                            TextField("Host path", text: $mount.host)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                            Button {
                                if let path = chooseDirectory() { mount.host = path }
                            } label: { Image(systemName: "folder") }
                                .buttonStyle(.borderless)
                            Button(role: .destructive) {
                                mounts.removeAll { $0.id == mount.id }
                            } label: { Image(systemName: "minus.circle.fill") }
                                .buttonStyle(.borderless)
                        }
                        HStack {
                            Image(systemName: "arrow.down").foregroundStyle(.secondary)
                            TextField("Container path (e.g. /data)", text: $mount.container)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                Button {
                    mounts.append(MountBind())
                } label: { Label("Add Mount", systemImage: "plus") }
                    .controlSize(.small)
            } header: {
                Text("Mounts")
            }

            Section {
                ForEach($envVars) { $env in
                    HStack {
                        TextField("KEY", text: $env.key)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Text("=").foregroundStyle(.secondary)
                        TextField("value", text: $env.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Button(role: .destructive) {
                            envVars.removeAll { $0.id == env.id }
                        } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                }
                Button {
                    envVars.append(EnvVar())
                } label: { Label("Add Variable", systemImage: "plus") }
                    .controlSize(.small)
            } header: {
                Text("Environment")
            }

            Section {
                ForEach($ports) { $port in
                    HStack {
                        TextField("host", text: $port.host)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("container", text: $port.container)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Button(role: .destructive) {
                            ports.removeAll { $0.id == port.id }
                        } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                }
                Button {
                    ports.append(PortPair())
                } label: { Label("Add Port", systemImage: "plus") }
                    .controlSize(.small)
            } header: {
                Text("Published Ports")
            }

            Section("Network") {
                Picker("Network", selection: $networkChoice) {
                    Text("Default").tag("")
                    ForEach(availableNetworks) { net in
                        Text(net.name).tag(net.name)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            availableNetworks = (try? await viewModel.runtime.listNetworks()) ?? []
        }
    }

    // MARK: - Docker Run

    private var dockerRunForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste your Docker run command:")
                .font(.headline)

            TextEditor(text: $dockerCommand)
                .font(.system(.body, design: .monospaced))
                .frame(maxHeight: .infinity)
                .border(Color.secondary.opacity(0.3))

            Text("Example: docker run -d --name my-nginx -p 8080:80 nginx:latest")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
        .padding()
    }

    // MARK: - Compose

    private var composeForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Project Name:")
                    .font(.headline)
                TextField("my-app", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }

            Text("Paste your docker-compose.yml content:")
                .font(.headline)

            TextEditor(text: $composeContent)
                .font(.system(.body, design: .monospaced))
                .frame(maxHeight: .infinity)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Button("Load Example") {
                    composeContent = DockerComposeParser.exampleComposeYAML()
                    projectName = "example-app"
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Text("Supports docker-compose.yml v2 and v3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Validation & submit

    private var isSubmitDisabled: Bool {
        switch mode {
        case .configure:
            return name.trimmed.isEmpty || image.trimmed.isEmpty
        case .dockerRun:
            return dockerCommand.trimmed.isEmpty
        case .compose:
            return composeContent.trimmed.isEmpty || projectName.trimmed.isEmpty
        }
    }

    private func submit() {
        errorMessage = nil
        isWorking = true

        Task {
            do {
                switch mode {
                case .configure:
                    var spec = ContainerSpec(
                        name: name.trimmed,
                        image: image.trimmed,
                        cpus: Int(cpus),
                        memoryBytes: UInt64(memoryGB * 1024 * 1024 * 1024),
                        command: parseCommand(command),
                        workingDirectory: workingDirectory.trimmed.isEmpty ? "/" : workingDirectory.trimmed
                    )
                    spec.environment = Dictionary(
                        envVars
                            .filter { !$0.key.trimmed.isEmpty }
                            .map { ($0.key.trimmed, $0.value) },
                        uniquingKeysWith: { _, last in last }
                    )
                    spec.publishedPorts = ports.compactMap { portSpec($0) }
                    spec.volumeBinds = mounts.compactMap { mountSpec($0) }
                    spec.network = networkChoice.isEmpty ? nil : networkChoice
                    spec.platform = platform == "auto" ? nil : platform
                    await viewModel.createContainer(spec: spec)

                case .dockerRun:
                    let spec = try DockerCommandParser.parseDockerRun(dockerCommand)
                    await viewModel.createContainer(spec: spec)

                case .compose:
                    _ = try await composeManager.createProject(
                        name: projectName.trimmed,
                        yamlContent: composeContent
                    )
                }
                dismiss()
            } catch {
                errorMessage = "Failed to add: \(error.localizedDescription)"
                isWorking = false
            }
        }
    }

    /// Empty command → `[]` so RuntimeCore passes no command and the image's
    /// own default entrypoint/command is used.
    private func parseCommand(_ command: String) -> [String] {
        let trimmed = command.trimmed
        guard !trimmed.isEmpty else { return [] }
        return trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }

    /// Build a `--publish` spec ("host:container") from a row, skipping incomplete rows.
    private func portSpec(_ pair: PortPair) -> String? {
        let host = pair.host.trimmed
        let container = pair.container.trimmed
        guard !host.isEmpty, !container.isEmpty else { return nil }
        return "\(host):\(container)"
    }

    /// Build a `--volume` spec ("host:container") from a mount row.
    private func mountSpec(_ mount: MountBind) -> String? {
        let host = mount.host.trimmed
        let container = mount.container.trimmed
        guard !host.isEmpty, !container.isEmpty else { return nil }
        return "\(host):\(container)"
    }

    /// Present a directory chooser and return the selected path.
    private func chooseDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

/// A resource input combining a slider with a numeric text field.
struct ResourceField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var unit: String = ""

    var body: some View {
        HStack(spacing: 12) {
            Slider(value: $value, in: range, step: step)
            HStack(spacing: 4) {
                TextField("", value: $value, format: .number.precision(.fractionLength(step < 1 ? 1 : 0)))
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                if !unit.isEmpty {
                    Text(unit).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview {
    let vm = ContainerViewModel()
    AddContainerView(viewModel: vm, composeManager: ComposeManager(runtime: vm.runtime))
}
