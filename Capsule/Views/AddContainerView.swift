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
        var subtitle: String {
            switch self {
            case .configure: return NSLocalizedString("Build manually", comment: "")
            case .dockerRun: return NSLocalizedString("Convert a command", comment: "")
            case .compose: return NSLocalizedString("Import services", comment: "")
            }
        }
        var icon: String {
            switch self {
            case .configure: return "slider.horizontal.3"
            case .dockerRun: return "terminal"
            case .compose: return "square.stack.3d.up"
            }
        }
    }

    /// One environment variable row.
    struct EnvVar: Identifiable { let id = UUID(); var key = ""; var value = "" }
    /// One published-port row (host → container).
    struct PortPair: Identifiable { let id = UUID(); var host = ""; var container = "" }
    /// One volume bind row (host path → container path).
    struct MountBind: Identifiable { let id = UUID(); var host = ""; var container = "" }
    struct EditableComposeService: Identifiable {
        let id = UUID()
        var serviceName: String
        var containerName: String
        var image: String
        var portsText: String
        var mountsText: String
        var envText: String
        var dependsText: String
        var networkText: String
        var restartPolicy: String
        var healthcheck: Bool
        var commandText: String

        init(_ service: ComposeProject.ComposeService) {
            serviceName = service.name
            containerName = service.containerName
            image = service.image
            portsText = service.portBindings.joined(separator: "\n")
            mountsText = service.volumes.joined(separator: "\n")
            envText = service.environment
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "\n")
            dependsText = service.dependsOn.joined(separator: ", ")
            networkText = service.networks.joined(separator: ", ")
            restartPolicy = service.restartPolicy ?? RestartPolicy.no.rawValue
            healthcheck = service.healthcheck
            commandText = service.command.joined(separator: " ")
        }

        func service() -> ComposeProject.ComposeService {
            let envPairs = envText.lines.compactMap { line -> (String, String)? in
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return (String(parts[0]).trimmed, String(parts[1]))
            }
            return ComposeProject.ComposeService(
                name: serviceName.trimmed,
                containerName: containerName.trimmed,
                image: image.trimmed,
                ports: [],
                portBindings: portsText.lines,
                volumes: mountsText.lines,
                environment: Dictionary(envPairs, uniquingKeysWith: { _, last in last }),
                dependsOn: dependsText.commaSeparated,
                networks: networkText.commaSeparated,
                restartPolicy: restartPolicy == RestartPolicy.no.rawValue ? nil : restartPolicy,
                healthcheck: healthcheck,
                cpus: 2,
                memoryGB: 2,
                command: commandText.trimmed.isEmpty ? [] : commandText.split(separator: " ").map(String.init)
            )
        }
    }

    static let platforms = ["auto", "linux/arm64", "linux/amd64"]

    enum ConfigSection: String, CaseIterable, Identifiable {
        case general, network, ports, volumes, environment, resources, lifecycle, advanced
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return NSLocalizedString("General", comment: "")
            case .network: return NSLocalizedString("Network", comment: "")
            case .ports: return NSLocalizedString("Ports", comment: "")
            case .volumes: return NSLocalizedString("Volumes", comment: "")
            case .environment: return NSLocalizedString("Environment", comment: "")
            case .resources: return NSLocalizedString("Resources", comment: "")
            case .lifecycle: return NSLocalizedString("Lifecycle", comment: "")
            case .advanced: return NSLocalizedString("Advanced", comment: "")
            }
        }
        var icon: String {
            switch self {
            case .general: return "cube"
            case .network: return "network"
            case .ports: return "arrow.left.arrow.right"
            case .volumes: return "externaldrive"
            case .environment: return "list.bullet"
            case .resources: return "cpu"
            case .lifecycle: return "repeat"
            case .advanced: return "gearshape"
            }
        }
    }

    @State private var mode: Mode = .configure
    @State private var configSection: ConfigSection = .general

    // Configure fields
    @State private var name = ""
    @State private var image = ""
    @State private var platform = "auto"
    @State private var cpus: Double = 2
    @State private var memoryGB = 2.0
    @State private var command = ""          // empty → use the image's default
    @State private var workingDirectory = ""
    @State private var envVars: [EnvVar] = []
    @State private var envFilesText = ""
    @State private var ports: [PortPair] = []
    @State private var publishedSocketsText = ""
    @State private var mounts: [MountBind] = []
    @State private var networkChoice = ""    // empty → default network
    @State private var availableNetworks: [ContainerCLI.NetworkInfo] = []
    @State private var restartPolicy: RestartPolicy = .no
    @State private var removeAfterStop = false
    @State private var readOnlyRootfs = false
    @State private var useInit = false
    @State private var rosettaEnabled = false
    @State private var entrypoint = ""
    @State private var user = ""
    @State private var uid = ""
    @State private var gid = ""
    @State private var labelsText = ""
    @State private var ulimitsText = ""
    @State private var dnsServersText = ""
    @State private var dnsSearchText = ""
    @State private var dnsOptionsText = ""
    @State private var noDNS = false
    @State private var tmpfsText = ""
    @State private var shmSize = ""
    @State private var capAddText = ""
    @State private var capDropText = ""
    @State private var interactive = false
    @State private var tty = false
    @State private var sshAgent = false
    @State private var virtualization = false

    // Docker Run import
    @State private var showDockerRunImport = false

    // Docker Run field
    @State private var dockerCommand = ""
    @State private var dockerParseError: String?

    // Compose fields
    @State private var projectName = ""
    @State private var composeContent = ""
    @State private var composeServices: [EditableComposeService] = []
    @State private var composeVolumesText = ""
    @State private var composeNetworksText = ""
    @State private var composeParseError: String?
    @State private var selectedComposeServiceID: UUID?

    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modeSwitcher
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

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
                    Button("Create") { submit(startAfterCreate: false) }
                        .disabled(isSubmitDisabled || isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create & Start") { submit(startAfterCreate: true) }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSubmitDisabled || isWorking || mode == .compose)
                }
            }
            .frame(width: 920, height: 680)
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 10) {
            ForEach(Mode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.title3)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(mode == item ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(mode == item ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Configure

    private var configureForm: some View {
        HSplitView {
            // Left sidebar: section navigation
            List(ConfigSection.allCases, selection: $configSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)

            // Right panel: selected section content
            ScrollView {
                VStack(spacing: 0) {
                    // Section header
                    HStack {
                        Label(configSection.title, systemImage: configSection.icon)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()

                        // Quick import from Docker Run
                        Button {
                            showDockerRunImport = true
                        } label: {
                            Label("Import Docker Run", systemImage: "terminal")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                    Divider()

                    // Section form content
                    Form {
                        switch configSection {
                        case .general: generalSection
                        case .network: networkSection
                        case .ports: portsSection
                        case .volumes: mountsSection
                        case .environment: environmentSection
                        case .resources: resourcesSection
                        case .lifecycle: lifecycleSection
                        case .advanced: advancedSection
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                }
            }
            .sheet(isPresented: $showDockerRunImport) {
                dockerRunImportSheet
            }
        }
        .task {
            availableNetworks = (try? await viewModel.runtime.listNetworks()) ?? []
        }
    }

    // MARK: - Config Sections

    private var generalSection: some View {
        Group {
            Section {
                TextField("Image", text: $image, prompt: Text("docker.io/library/nginx:latest"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Picker("Platform", selection: $platform) {
                    ForEach(Self.platforms, id: \.self) { Text($0).tag($0) }
                }
                TextField("Name", text: $name, prompt: Text(suggestedName))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("Image")
            }

            if !image.trimmed.isEmpty {
                Section {
                    TextField("Entrypoint", text: $entrypoint, prompt: Text("Use image default"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    TextField("Command", text: $command, prompt: Text("Use image default"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    TextField("Working Directory", text: $workingDirectory, prompt: Text("/"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Execution")
                }

                Section {
                    TextField("User", text: $user, prompt: Text("name or uid:gid"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        TextField("UID", text: $uid)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        TextField("GID", text: $gid)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    Toggle("Interactive stdin", isOn: $interactive)
                    Toggle("Allocate TTY", isOn: $tty)
                } header: {
                    Text("User & TTY")
                }
            }
        }
    }

    private var networkSection: some View {
        Group {
            Section {
                Picker("Network", selection: $networkChoice) {
                    Text("Default").tag("")
                    Text("Host").tag("host")
                    Text("Bridge").tag("bridge")
                    ForEach(availableNetworks) { net in
                        Text(net.name).tag(net.name)
                    }
                }
            } header: {
                Text("Network Mode")
            }

            Section {
                TextField("Published sockets", text: $publishedSocketsText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...3)
            } header: {
                Text("Sockets")
            }
        }
    }

    private var resourcesSection: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPUs")
                    ResourceField(value: $cpus, range: 1...8, step: 1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory")
                    ResourceField(value: $memoryGB, range: 0.5...16, step: 0.5, unit: "GB")
                }
            } header: {
                Text("Compute")
            }
        }
    }

    private var lifecycleSection: some View {
        Group {
            Section {
                Picker("Restart", selection: $restartPolicy) {
                    ForEach(RestartPolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
            } header: {
                Text("Restart Policy")
            }

            Section {
                Toggle("Remove after stop", isOn: $removeAfterStop)
                Toggle("Run with init process", isOn: $useInit)
                Toggle("Read-only root filesystem", isOn: $readOnlyRootfs)
                Toggle("Enable Rosetta for amd64 images", isOn: $rosettaEnabled)
            } header: {
                Text("Container Options")
            }
        }
    }

    private var advancedSection: some View {
        Group {
            Section {
                TextField("Labels", text: $labelsText, prompt: Text("com.example.key=value"), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...4)
                TextField("Ulimits", text: $ulimitsText, prompt: Text("nofile=1024:2048"), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...4)
            } header: {
                Text("Labels & Limits")
            }

            Section {
                TextField("DNS servers", text: $dnsServersText, prompt: Text("1.1.1.1"), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...3)
                TextField("DNS search domains", text: $dnsSearchText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...3)
                TextField("DNS options", text: $dnsOptionsText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...3)
                Toggle("Disable DNS configuration", isOn: $noDNS)
            } header: {
                Text("DNS")
            }

            Section {
                TextField("tmpfs mounts", text: $tmpfsText, prompt: Text("/run"), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...4)
                TextField("Shared memory size", text: $shmSize, prompt: Text("64MB"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("Filesystem")
            }

            Section {
                TextField("Add capabilities", text: $capAddText, prompt: Text("NET_ADMIN"), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...3)
                TextField("Drop capabilities", text: $capDropText, prompt: Text("ALL"), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...3)
            } header: {
                Text("Capabilities")
            }

            Section {
                Toggle("Forward SSH agent", isOn: $sshAgent)
                Toggle("Use virtualization framework", isOn: $virtualization)
            } header: {
                Text("System Integration")
            }
        }
    }

    // MARK: - Docker Run

    private var dockerRunImportSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextEditor(text: $dockerCommand)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 180)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if let dockerParseError {
                    Label(dockerParseError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("Paste a docker run command. Capsule will parse it and fill the configuration form.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Import Docker Run")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDockerRunImport = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Parse") {
                        parseDockerRunIntoConfigure()
                        if dockerParseError == nil {
                            showDockerRunImport = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(dockerCommand.trimmed.isEmpty)
                }
            }
            .frame(width: 580, height: 380)
        }
    }

    private var dockerRunForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Paste Docker Run", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                Button("Parse to Configure") {
                    parseDockerRunIntoConfigure()
                }
                .buttonStyle(.borderedProminent)
                .disabled(dockerCommand.trimmed.isEmpty)
            }

            TextEditor(text: $dockerCommand)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 150)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if let dockerParseError {
                Label(dockerParseError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("After parsing, Capsule fills the Configure form so every field can be reviewed and edited before creation.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    private func parseDockerRunIntoConfigure() {
        do {
            let spec = try DockerCommandParser.parseDockerRun(dockerCommand)
            apply(spec: spec)
            dockerParseError = nil
            mode = .configure
        } catch {
            dockerParseError = error.localizedDescription
        }
    }

    private func apply(spec: ContainerSpec) {
        name = spec.name
        image = spec.image
        platform = spec.platform ?? "auto"
        cpus = Double(spec.cpus)
        memoryGB = Double(spec.memoryBytes) / 1024 / 1024 / 1024
        command = spec.command.joined(separator: " ")
        workingDirectory = spec.workingDirectory
        envVars = spec.environment.sorted { $0.key < $1.key }.map { EnvVar(key: $0.key, value: $0.value) }
        envFilesText = spec.envFiles.joined(separator: "\n")
        ports = spec.publishedPorts.map { value in
            let parts = value.split(separator: ":")
            if parts.count >= 2 {
                let host = parts.dropLast().joined(separator: ":")
                return PortPair(host: host, container: String(parts[parts.count - 1]))
            }
            return PortPair(host: "", container: value)
        }
        publishedSocketsText = spec.publishedSockets.joined(separator: "\n")
        mounts = spec.volumeBinds.map { value in
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            return MountBind(host: parts.first ?? "", container: parts.count > 1 ? parts[1] : "")
        }
        networkChoice = spec.network ?? ""
        restartPolicy = spec.restartPolicy
        removeAfterStop = spec.removeAfterStop
        readOnlyRootfs = spec.readOnlyRootfs
        useInit = spec.useInit
        rosettaEnabled = spec.rosettaEnabled
        entrypoint = spec.entrypoint ?? ""
        user = spec.user ?? ""
        uid = spec.uid ?? ""
        gid = spec.gid ?? ""
        labelsText = spec.labels.joined(separator: "\n")
        ulimitsText = spec.ulimits.joined(separator: "\n")
        dnsServersText = spec.dnsServers.joined(separator: "\n")
        dnsSearchText = spec.dnsSearchDomains.joined(separator: "\n")
        dnsOptionsText = spec.dnsOptions.joined(separator: "\n")
        noDNS = spec.noDNS
        tmpfsText = spec.tmpfs.joined(separator: "\n")
        shmSize = spec.shmSize ?? ""
        capAddText = spec.capAdd.joined(separator: "\n")
        capDropText = spec.capDrop.joined(separator: "\n")
        interactive = spec.interactive
        tty = spec.tty
        sshAgent = spec.sshAgent
        virtualization = spec.virtualization
    }

    // MARK: - Compose

    private var composeForm: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Import Compose", systemImage: "square.stack.3d.up")
                        .font(.headline)
                    Spacer()
                    TextField("Project", text: $projectName, prompt: Text("my-app"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    Button("Parse") {
                        parseComposeIntoEditableServices()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(composeContent.trimmed.isEmpty)
                }

                TextEditor(text: $composeContent)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: composeServices.isEmpty ? 360 : 150)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button("Load Example") {
                        composeContent = DockerComposeParser.exampleComposeYAML()
                        projectName = "example-app"
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text("Supports common Compose v2/v3 service fields")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let composeParseError {
                    Label(composeParseError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()

            if !composeServices.isEmpty {
                Divider()
                composeEditablePlan
            }
        }
    }

    private var composeEditablePlan: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Compose Services", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text("\(composeServices.count) containers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Project volumes", text: $composeVolumesText)
                    .textFieldStyle(.roundedBorder)
                TextField("Project networks", text: $composeNetworksText)
                    .textFieldStyle(.roundedBorder)
            }

            HSplitView {
                List(selection: $selectedComposeServiceID) {
                    ForEach(composeServices) { service in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(service.containerName.isEmpty ? service.serviceName : service.containerName)
                                .fontWeight(.semibold)
                            Text(service.image)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                        .tag(service.id)
                    }
                }
                .frame(minWidth: 210, idealWidth: 240)

                if let binding = selectedComposeServiceBinding {
                    editableComposeServiceForm(binding)
                        .frame(minWidth: 520)
                } else {
                    ContentUnavailableView("Select a service", systemImage: "square.stack.3d.up")
                        .frame(minWidth: 520)
                }
            }
        }
        .padding()
    }

    private var selectedComposeServiceBinding: Binding<EditableComposeService>? {
        guard let selectedComposeServiceID,
              let index = composeServices.firstIndex(where: { $0.id == selectedComposeServiceID }) else {
            return nil
        }
        return $composeServices[index]
    }

    private func editableComposeServiceForm(_ service: Binding<EditableComposeService>) -> some View {
        HSplitView {
            // Left sidebar: section navigation
            List(ConfigSection.allCases, selection: $configSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)

            // Right panel: selected section content
            ScrollView {
                VStack(spacing: 0) {
                    // Section header
                    HStack {
                        Label(configSection.title, systemImage: configSection.icon)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                    Divider()

                    // Section form content
                    Form {
                        switch configSection {
                        case .general: composeGeneralSection(service)
                        case .network: composeNetworkSection(service)
                        case .ports: composePortsSection(service)
                        case .volumes: composeVolumesSection(service)
                        case .environment: composeEnvironmentSection(service)
                        case .resources: Text("Resources are set at project level").foregroundStyle(.secondary)
                        case .lifecycle: composeLifecycleSection(service)
                        case .advanced: Text("Advanced settings inherit from service definition").foregroundStyle(.secondary)
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                }
            }
        }
    }

    // MARK: - Compose Service Sections

    private func composeGeneralSection(_ service: Binding<EditableComposeService>) -> some View {
        Group {
            Section {
                TextField("Image", text: service.image)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                TextField("Container name", text: service.containerName)
                    .textFieldStyle(.roundedBorder)
                TextField("Service name", text: service.serviceName)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Image")
            }

            Section {
                TextField("Command", text: service.commandText, prompt: Text("Override image command"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("Execution")
            }
        }
    }

    private func composeNetworkSection(_ service: Binding<EditableComposeService>) -> some View {
        Group {
            Section {
                TextField("Networks", text: service.networkText, prompt: Text("network1, network2"))
                    .textFieldStyle(.roundedBorder)
                TextField("Depends on", text: service.dependsText, prompt: Text("service1, service2"))
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Network & Dependencies")
            }
        }
    }

    private func composePortsSection(_ service: Binding<EditableComposeService>) -> some View {
        Section {
            TextField("One mapping per line (e.g. 8080:80)", text: service.portsText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2...8)
        } header: {
            Text("Port Mappings")
        }
    }

    private func composeVolumesSection(_ service: Binding<EditableComposeService>) -> some View {
        Section {
            TextField("One mount per line (e.g. ./data:/var/lib/data)", text: service.mountsText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2...8)
        } header: {
            Text("Mounts")
        }
    }

    private func composeEnvironmentSection(_ service: Binding<EditableComposeService>) -> some View {
        Section {
            TextField("One variable per line (KEY=value)", text: service.envText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2...10)
        } header: {
            Text("Environment Variables")
        }
    }

    private func composeLifecycleSection(_ service: Binding<EditableComposeService>) -> some View {
        Group {
            Section {
                Picker("Restart", selection: service.restartPolicy) {
                    ForEach(RestartPolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy.rawValue)
                    }
                }
            } header: {
                Text("Restart Policy")
            }

            Section {
                Toggle("Has healthcheck", isOn: service.healthcheck)
            } header: {
                Text("Health")
            }
        }
    }

    private func parseComposeIntoEditableServices() {
        do {
            if projectName.trimmed.isEmpty {
                projectName = "compose-app"
            }
            let parsed = try DockerComposeParser.parse(yamlContent: composeContent, appName: projectName.trimmed)
            projectName = parsed.name
            composeServices = parsed.services.map(EditableComposeService.init)
            composeVolumesText = parsed.volumes.joined(separator: ", ")
            composeNetworksText = parsed.networks.joined(separator: ", ")
            selectedComposeServiceID = composeServices.first?.id
            composeParseError = nil
        } catch {
            composeParseError = error.localizedDescription
        }
    }

    // MARK: - Validation & submit

    private var isSubmitDisabled: Bool {
        switch mode {
        case .configure:
            return image.trimmed.isEmpty
        case .dockerRun:
            return true
        case .compose:
            return projectName.trimmed.isEmpty || composeServices.isEmpty
        }
    }

    private var mountsSection: some View {
        Section {
            ForEach($mounts) { $mount in
                VStack(spacing: 6) {
                    HStack {
                        TextField("Host path or volume", text: $mount.host)
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
            Button { mounts.append(MountBind()) } label: {
                Label("Add Mount", systemImage: "plus")
            }
            .controlSize(.small)
        } header: {
            Text("Mounts")
        }
    }

    private var environmentSection: some View {
        Section {
            ForEach($envVars) { $env in
                HStack {
                    TextField("KEY", text: $env.key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Text("=")
                        .foregroundStyle(.secondary)
                    TextField("value", text: $env.value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button(role: .destructive) {
                        envVars.removeAll { $0.id == env.id }
                    } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                }
            }
            Button { envVars.append(EnvVar()) } label: {
                Label("Add Variable", systemImage: "plus")
            }
            .controlSize(.small)

            TextField("Env files", text: $envFilesText, prompt: Text("/path/to/.env"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1...4)
        } header: {
            Text("Environment")
        }
    }

    private var portsSection: some View {
        Section {
            if !canPublishPorts {
                Text("Port publishing is disabled when using host networking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($ports) { $port in
                    HStack {
                        TextField("host", text: $port.host)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("container", text: $port.container)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Button(role: .destructive) {
                            ports.removeAll { $0.id == port.id }
                        } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                }
                Button { ports.append(PortPair()) } label: {
                    Label("Add Port", systemImage: "plus")
                }
                .controlSize(.small)
            }
        } header: {
            Text("Port Mappings")
        }
    }

    private var canPublishPorts: Bool {
        networkChoice != "host"
    }

    private var creationPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Preview", systemImage: "terminal")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                previewRow("Name", resolvedName)
                previewRow("Image", image.trimmed.isEmpty ? "Required" : image.trimmed)
                previewRow("Resources", "\(Int(cpus)) CPU / \(memoryGB.formatted(.number.precision(.fractionLength(1)))) GB")
                previewRow("Network", networkChoice.isEmpty ? "default" : networkChoice)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(commandPreview)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            Text("Capsule creates the container first. Use Create & Start when you want the payload to run immediately.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func previewRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
        }
        .font(.caption)
    }

    private var suggestedName: String {
        let base = image.trimmed
            .split(separator: "/").last?
            .split(separator: ":").first
            .map(String.init) ?? "my-container"
        return base.isEmpty ? "my-container" : base.replacingOccurrences(of: ".", with: "-")
    }

    private var resolvedName: String {
        name.trimmed.isEmpty ? suggestedName : name.trimmed
    }

    private var commandPreview: String {
        var parts = ["container", "create", "--name", shellEscape(resolvedName)]
        parts += ["--cpus", "\(Int(cpus))", "--memory", "\(Int(memoryGB * 1024))MB"]
        envVars
            .filter { !$0.key.trimmed.isEmpty }
            .forEach { parts += ["--env", shellEscape("\($0.key.trimmed)=\($0.value)")] }
        if canPublishPorts {
            ports.compactMap(portSpec).forEach { parts += ["--publish", shellEscape($0)] }
        }
        mounts.compactMap(mountSpec).forEach { parts += ["--volume", shellEscape($0)] }
        if !networkChoice.isEmpty { parts += ["--network", shellEscape(networkChoice)] }
        if platform != "auto" { parts += ["--platform", platform] }
        if !workingDirectory.trimmed.isEmpty, workingDirectory.trimmed != "/" {
            parts += ["--workdir", shellEscape(workingDirectory.trimmed)]
        }
        if rosettaEnabled { parts.append("--rosetta") }
        if removeAfterStop { parts.append("--rm") }
        if readOnlyRootfs { parts.append("--read-only") }
        if useInit { parts.append("--init") }
        parts.append(shellEscape(image.trimmed.isEmpty ? "<image>" : image.trimmed))
        parts += parseCommand(command).map(shellEscape)
        return parts.joined(separator: " ")
    }

    private func containerCommandPreview(for spec: ContainerSpec) -> String {
        var parts = ["container", "create", "--name", shellEscape(spec.name)]
        parts += ["--cpus", "\(spec.cpus)", "--memory", "\(Int(spec.memoryBytes / 1024 / 1024))MB"]
        spec.environment.sorted(by: { $0.key < $1.key }).forEach { parts += ["--env", shellEscape("\($0.key)=\($0.value)")] }
        spec.publishedPorts.forEach { parts += ["--publish", shellEscape($0)] }
        spec.volumeBinds.forEach { parts += ["--volume", shellEscape($0)] }
        if let network = spec.network { parts += ["--network", shellEscape(network)] }
        if let platform = spec.platform { parts += ["--platform", platform] }
        if spec.workingDirectory != "/" { parts += ["--workdir", shellEscape(spec.workingDirectory)] }
        if spec.removeAfterStop { parts.append("--rm") }
        parts.append(shellEscape(spec.image))
        parts += spec.command.map(shellEscape)
        return parts.joined(separator: " ")
    }

    private func templateButton(_ title: String, imageName: String, image: String, port: (String, String)) -> some View {
        Button {
            self.image = image
            if name.trimmed.isEmpty { name = image.split(separator: ":").first.map(String.init) ?? title.lowercased() }
            if !ports.contains(where: { $0.host == port.0 && $0.container == port.1 }) {
                ports.append(PortPair(host: port.0, container: port.1))
            }
        } label: {
            Label(title, systemImage: imageName)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func submit(startAfterCreate: Bool) {
        errorMessage = nil
        isWorking = true

        Task {
            do {
                switch mode {
                case .configure:
                    var spec = ContainerSpec(
                        name: resolvedName,
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
                    spec.envFiles = envFilesText.lines
                    spec.publishedPorts = canPublishPorts ? ports.compactMap { portSpec($0) } : []
                    spec.publishedSockets = canPublishPorts ? publishedSocketsText.lines : []
                    spec.volumeBinds = mounts.compactMap { mountSpec($0) }
                    spec.network = networkChoice.isEmpty ? nil : networkChoice
                    spec.platform = platform == "auto" ? nil : platform
                    spec.entrypoint = entrypoint.nilIfTrimmedEmpty
                    spec.user = user.nilIfTrimmedEmpty
                    spec.uid = uid.nilIfTrimmedEmpty
                    spec.gid = gid.nilIfTrimmedEmpty
                    spec.labels = labelsText.lines
                    spec.ulimits = ulimitsText.lines
                    spec.dnsServers = dnsServersText.lines
                    spec.dnsSearchDomains = dnsSearchText.lines
                    spec.dnsOptions = dnsOptionsText.lines
                    spec.noDNS = noDNS
                    spec.tmpfs = tmpfsText.lines
                    spec.shmSize = shmSize.nilIfTrimmedEmpty
                    spec.capAdd = capAddText.lines
                    spec.capDrop = capDropText.lines
                    spec.interactive = interactive
                    spec.tty = tty
                    spec.sshAgent = sshAgent
                    spec.virtualization = virtualization
                    spec.rosettaEnabled = rosettaEnabled
                    spec.removeAfterStop = removeAfterStop
                    spec.readOnlyRootfs = readOnlyRootfs
                    spec.useInit = useInit
                    spec.restartPolicy = restartPolicy
                    if startAfterCreate {
                        let summary = try await viewModel.runtime.createContainer(spec)
                        try await viewModel.runtime.startContainer(id: summary.id)
                        await viewModel.refresh()
                    } else {
                        await viewModel.createContainer(spec: spec)
                    }

                case .dockerRun:
                    parseDockerRunIntoConfigure()
                    isWorking = false
                    return

                case .compose:
                    _ = try await composeManager.createProject(
                        name: projectName.trimmed,
                        services: composeServices.map { $0.service() },
                        volumes: composeVolumesText.commaSeparated,
                        networks: composeNetworksText.commaSeparated
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

    private func shellEscape(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if value.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
    var nilIfTrimmedEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
    var lines: [String] {
        components(separatedBy: .newlines)
            .map(\.trimmed)
            .filter { !$0.isEmpty }
    }
    var commaSeparated: [String] {
        split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }
}

#Preview {
    let vm = ContainerViewModel()
    AddContainerView(viewModel: vm, composeManager: ComposeManager(runtime: vm.runtime))
}
