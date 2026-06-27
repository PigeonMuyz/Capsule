import SwiftUI
import AppKit

struct CreateContainerPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ContainerViewModel
    @ObservedObject var composeManager: ComposeManager

    @State private var mode: CreateContainerMode = .container
    @State private var singleDraft = EditableContainerDraft()
    @State private var composeDrafts: [EditableContainerDraft] = []
    @State private var projectName = ""
    @State private var composeContent = ""
    @State private var composeVolumesText = ""
    @State private var composeNetworksText = ""
    @State private var composeParseError: String?

    @State private var showDockerRunImport = false
    @State private var dockerRunCommand = ""
    @State private var dockerRunError: String?

    @State private var availableNetworks: [ContainerCLI.NetworkInfo] = []
    @State private var startImmediately = true
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if mode == .container {
                        ContainerDraftCard(
                            draft: $singleDraft,
                            availableNetworks: availableNetworks,
                            variant: .single,
                            title: String(localized: "Container"),
                            canRemove: false,
                            onRemove: {}
                        )
                    } else {
                        composeImportPanel
                        composeCards
                    }
                }
                .padding(20)
            }

            if let message = errorMessage {
                Divider()
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.08))
            }

            Divider()
            footer
        }
        .frame(width: 640, height: 680)
        .task {
            availableNetworks = (try? await viewModel.runtime.listNetworks()) ?? []
        }
        .sheet(isPresented: $showDockerRunImport) {
            dockerRunImportSheet
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: mode == .container ? "cube.transparent" : "square.stack.3d.up")
                .font(.title3)
                .foregroundStyle(.cyan)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            importMenu
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var headerTitle: LocalizedStringKey {
        switch mode {
        case .container:
            return "Create Container"
        case .compose:
            return "Create Compose Project"
        }
    }

    private var headerSubtitle: LocalizedStringKey {
        switch mode {
        case .container:
            return startImmediately
                ? "Runs detached with the image's default command."
                : "Creates the container and leaves it stopped."
        case .compose:
            return "Parsed services become editable container cards."
        }
    }

    private var importMenu: some View {
        Menu {
            Button {
                showDockerRunImport = true
            } label: {
                Label("Import Docker Run", systemImage: "terminal")
            }

            Button {
                mode = .compose
            } label: {
                Label("Import Compose", systemImage: "square.stack.3d.up")
            }
        } label: {
            Image(systemName: "square.and.arrow.down")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .help("Import")
    }

    private var composeImportPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelRow("Project") {
                TextField("my-app", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
            }

            PanelRow("Compose") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $composeContent)
                        .font(.system(.caption, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: composeDrafts.isEmpty ? 230 : 120)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2))
                        }

                    HStack {
                        Button {
                            loadExampleCompose()
                        } label: {
                            Image(systemName: "doc.text")
                        }
                        .help("Load example")

                        Spacer()

                        Button {
                            try? parseComposeIntoCards()
                        } label: {
                            Label("Parse", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(composeContent.trimmed.isEmpty)
                    }

                    if let composeParseError {
                        Label(composeParseError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if !composeDrafts.isEmpty {
                composeProjectData
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.14))
        }
    }

    private var composeProjectData: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(.cyan)
                Text("Project Data")
                    .font(.callout.weight(.semibold))
                Text("Top-level Compose resources")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            VStack(spacing: 8) {
                ComposeProjectDataField(
                    title: "Volumes",
                    icon: "externaldrive",
                    text: $composeVolumesText,
                    placeholder: "No project volumes"
                )
                ComposeProjectDataField(
                    title: "Networks",
                    icon: "network",
                    text: $composeNetworksText,
                    placeholder: "No project networks"
                )
            }
        }
        .padding(.top, 2)
    }

    private var composeCards: some View {
        VStack(spacing: 12) {
            ForEach($composeDrafts) { $draft in
                ContainerDraftCard(
                    draft: $draft,
                    availableNetworks: availableNetworks,
                    variant: .compose,
                    title: draft.cardTitle,
                    canRemove: composeDrafts.count > 1,
                    onRemove: {
                        composeDrafts.removeAll { $0.id == draft.id }
                    }
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if mode == .container {
                Toggle("Start immediately", isOn: $startImmediately)
                    .toggleStyle(.switch)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isWorking)

            Button {
                submit()
            } label: {
                Text(createButtonTitle)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isCreateDisabled || isWorking)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var createButtonTitle: LocalizedStringKey {
        switch mode {
        case .container:
            return "Create"
        case .compose:
            return "Create Project"
        }
    }

    private var isCreateDisabled: Bool {
        switch mode {
        case .container:
            return singleDraft.image.trimmed.isEmpty
        case .compose:
            if composeDrafts.isEmpty {
                return composeContent.trimmed.isEmpty
            }
            return composeDrafts.contains { $0.image.trimmed.isEmpty || $0.serviceName.trimmed.isEmpty }
        }
    }

    private var dockerRunImportSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $dockerRunCommand)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 240)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2))
                    }

                if let dockerRunError {
                    Label(dockerRunError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Import Docker Run")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showDockerRunImport = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importDockerRun()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(dockerRunCommand.trimmed.isEmpty)
                }
            }
            .frame(width: 620, height: 420)
        }
    }

    private func submit() {
        errorMessage = nil

        do {
            switch mode {
            case .container:
                createSingleContainer()
            case .compose:
                try createComposeProject()
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createSingleContainer() {
        let spec = singleDraft.containerSpec(defaultName: singleDraft.resolvedContainerName)
        viewModel.createContainerInBackground(spec: spec, startImmediately: startImmediately)
    }

    private func createComposeProject() throws {
        if composeDrafts.isEmpty {
            try parseComposeIntoCards(throwOnFailure: true)
        }
        guard !composeDrafts.isEmpty else {
            throw CreateContainerPanelError.noComposeServices
        }

        let name = projectName.trimmed.isEmpty ? "compose-app" : projectName.trimmed
        composeManager.createProjectInBackground(
            name: name,
            services: composeDrafts.map { $0.composeService() },
            volumes: composeVolumesText.commaSeparated,
            networks: composeNetworksText.commaSeparated
        )
    }

    private func parseComposeIntoCards(throwOnFailure: Bool = false) throws {
        do {
            let name = projectName.trimmed.isEmpty ? "compose-app" : projectName.trimmed
            let parsed = try DockerComposeParser.parse(yamlContent: composeContent, appName: name)
            guard !parsed.services.isEmpty else {
                throw CreateContainerPanelError.noComposeServices
            }

            projectName = parsed.name
            composeDrafts = parsed.services.map(EditableContainerDraft.init)
            composeVolumesText = parsed.volumes.joined(separator: ", ")
            composeNetworksText = parsed.networks.joined(separator: ", ")
            composeParseError = nil
        } catch {
            composeParseError = error.localizedDescription
            if throwOnFailure {
                throw error
            }
        }
    }

    private func importDockerRun() {
        do {
            let spec = try DockerCommandParser.parseDockerRun(dockerRunCommand)
            singleDraft = EditableContainerDraft(spec: spec)
            mode = .container
            dockerRunError = nil
            showDockerRunImport = false
        } catch {
            dockerRunError = error.localizedDescription
        }
    }

    private func loadExampleCompose() {
        composeContent = DockerComposeParser.exampleComposeYAML()
        projectName = "example-app"
        try? parseComposeIntoCards()
    }
}

private enum CreateContainerMode {
    case container
    case compose
}

private enum DraftCardVariant {
    case single
    case compose
}

private enum CreateContainerPanelError: LocalizedError {
    case noComposeServices

    var errorDescription: String? {
        switch self {
        case .noComposeServices:
            return String(localized: "No services found in Compose file.")
        }
    }
}

private struct EditableContainerDraft: Identifiable {
    let id = UUID()
    var serviceName = "web"
    var containerName = ""
    var image = ""
    var command = ""
    var ports: [DraftPort] = [DraftPort()]
    var environmentText = ""
    var volumes: [DraftVolume] = []
    var networkChoice = ""
    var networksText = ""
    var dependsText = ""
    var cpus = 2
    var memoryGB = 2.0
    var restartPolicy: RestartPolicy = .no
    var removeAfterStop = false
    var sshAgent = false
    var healthcheck = false

    init() {}

    init(spec: ContainerSpec) {
        serviceName = spec.name.isEmpty ? "web" : spec.name
        containerName = spec.name
        image = spec.image
        command = spec.command.joined(separator: " ")
        ports = Self.portRows(from: spec.publishedPorts)
        environmentText = Self.environmentText(from: spec.environment)
        volumes = Self.volumeRows(from: spec.volumeBinds)
        networkChoice = spec.network ?? ""
        cpus = spec.cpus
        memoryGB = Double(spec.memoryBytes) / 1024 / 1024 / 1024
        restartPolicy = spec.restartPolicy
        removeAfterStop = spec.removeAfterStop
        sshAgent = spec.sshAgent
    }

    init(service: ComposeProject.ComposeService) {
        serviceName = service.name
        containerName = service.containerName == service.name ? "" : service.containerName
        image = service.image
        command = ShellCommandTokenizer.join(service.command)
        ports = Self.portRows(from: service.portBindings.isEmpty
            ? service.ports.map { "\($0.host):\($0.container)" }
            : service.portBindings
        )
        environmentText = Self.environmentText(from: service.environment)
        volumes = Self.volumeRows(from: service.volumes)
        networksText = service.networks.joined(separator: ", ")
        dependsText = service.dependsOn.joined(separator: ", ")
        cpus = service.cpus
        memoryGB = Double(service.memoryGB)
        restartPolicy = RestartPolicy(rawValue: service.restartPolicy ?? "") ?? .no
        healthcheck = service.healthcheck
    }

    var cardTitle: String {
        if !containerName.trimmed.isEmpty {
            return containerName.trimmed
        }
        return serviceName.trimmed.isEmpty ? resolvedContainerName : serviceName.trimmed
    }

    var resolvedContainerName: String {
        if !containerName.trimmed.isEmpty {
            return containerName.trimmed
        }
        let base = image.trimmed
            .split(separator: "/").last?
            .split(separator: ":").first
            .map(String.init) ?? "my-container"
        return base.isEmpty ? "my-container" : base.replacingOccurrences(of: ".", with: "-")
    }

    func containerSpec(defaultName: String) -> ContainerSpec {
        var spec = ContainerSpec(
            name: containerName.trimmed.isEmpty ? defaultName : containerName.trimmed,
            image: image.trimmed,
            cpus: cpus,
            memoryBytes: UInt64(memoryGB * 1024 * 1024 * 1024),
            command: parseCommand(command),
            workingDirectory: "/"
        )
        spec.publishedPorts = ports.compactMap(\.spec)
        spec.volumeBinds = volumes.compactMap(\.spec)
        spec.environment = environmentDictionary
        spec.network = networkChoice.trimmed.isEmpty ? nil : networkChoice.trimmed
        spec.restartPolicy = restartPolicy
        spec.removeAfterStop = removeAfterStop
        spec.sshAgent = sshAgent
        return spec
    }

    func composeService() -> ComposeProject.ComposeService {
        ComposeProject.ComposeService(
            name: serviceName.trimmed,
            containerName: containerName.trimmed,
            image: image.trimmed,
            ports: [],
            portBindings: ports.compactMap(\.spec),
            volumes: volumes.compactMap(\.spec),
            environment: environmentDictionary,
            dependsOn: dependsText.commaSeparated,
            networks: networksText.commaSeparated,
            restartPolicy: restartPolicy == .no ? nil : restartPolicy.rawValue,
            healthcheck: healthcheck,
            cpus: cpus,
            memoryGB: Int(memoryGB.rounded()),
            command: parseCommand(command)
        )
    }

    private func parseCommand(_ value: String) -> [String] {
        ShellCommandTokenizer.split(value.trimmed)
    }

    private var environmentDictionary: [String: String] {
        Dictionary(Self.environmentPairs(from: environmentText), uniquingKeysWith: { _, last in last })
    }

    private static func environmentText(from environment: [String: String]) -> String {
        environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }

    private static func environmentPairs(from text: String) -> [(String, String)] {
        text
            .components(separatedBy: .newlines)
            .compactMap { line -> (String, String)? in
                let trimmedLine = line.trimmed
                guard !trimmedLine.isEmpty else { return nil }
                let parts = trimmedLine.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let key = parts.first.map(String.init)?.trimmed, !key.isEmpty else {
                    return nil
                }
                let value = parts.count > 1 ? String(parts[1]) : ""
                return (key, value)
            }
    }

    private static func portRows(from specs: [String]) -> [DraftPort] {
        let rows = specs.map { spec -> DraftPort in
            let split = spec.split(separator: "/", maxSplits: 1).map(String.init)
            let mapping = split.first ?? spec
            let proto = split.count > 1 ? split[1] : "tcp"
            let parts = mapping.split(separator: ":").map(String.init)
            if parts.count >= 2 {
                return DraftPort(
                    host: parts.dropLast().joined(separator: ":"),
                    container: parts.last ?? "",
                    proto: proto.isEmpty ? "tcp" : proto
                )
            }
            return DraftPort(host: "", container: mapping, proto: proto.isEmpty ? "tcp" : proto)
        }
        return rows.isEmpty ? [DraftPort()] : rows
    }

    private static func volumeRows(from specs: [String]) -> [DraftVolume] {
        specs.map { spec -> DraftVolume in
            let parts = spec.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else {
                return DraftVolume(source: spec, target: "")
            }
            let readOnly = parts.last == "ro"
            let targetEnd = readOnly ? parts.count - 1 : parts.count
            let target = parts[1..<targetEnd].joined(separator: ":")
            return DraftVolume(source: parts[0], target: target, readOnly: readOnly)
        }
    }
}

private struct DraftPort: Identifiable {
    let id = UUID()
    var host = ""
    var container = ""
    var proto = "tcp"

    var spec: String? {
        let h = host.trimmed
        let c = container.trimmed
        guard !h.isEmpty, !c.isEmpty else { return nil }
        let mapping = "\(h):\(c)"
        return proto == "tcp" ? mapping : "\(mapping)/\(proto)"
    }
}

private struct DraftVolume: Identifiable {
    let id = UUID()
    var source = ""
    var target = ""
    var readOnly = false

    var spec: String? {
        let s = source.trimmed
        let t = target.trimmed
        guard !s.isEmpty, !t.isEmpty else { return nil }
        return readOnly ? "\(s):\(t):ro" : "\(s):\(t)"
    }
}

private struct ComposeProjectDataField: View {
    let title: LocalizedStringKey
    let icon: String
    @Binding var text: String
    let placeholder: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 96, alignment: .leading)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.secondary.opacity(0.16))
                }
        }
    }
}

private struct ContainerDraftCard: View {
    @Binding var draft: EditableContainerDraft
    let availableNetworks: [ContainerCLI.NetworkInfo]
    let variant: DraftCardVariant
    let title: String
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "cube.box")
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Group {
                        if draft.image.trimmed.isEmpty {
                            Text("No image selected")
                        } else {
                            Text(draft.image.trimmed)
                        }
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if canRemove {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove service")
                }
            }

            if variant == .compose {
                PanelRow("Service") {
                    HStack {
                        TextField("web", text: $draft.serviceName)
                            .textFieldStyle(.roundedBorder)
                        TextField("container name", text: $draft.containerName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            PanelRow("Image") {
                TextField("postgres:latest", text: $draft.image)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            if variant == .single {
                PanelRow("Name") {
                    TextField(draft.resolvedContainerName, text: $draft.containerName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            PanelRow("Ports") {
                VStack(spacing: 6) {
                    ForEach($draft.ports) { $port in
                        HStack(spacing: 6) {
                            TextField("host", text: $port.host)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 90)
                            Text(":")
                                .foregroundStyle(.secondary)
                            TextField("5432", text: $port.container)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 86)
                            Picker("", selection: $port.proto) {
                                Text("tcp").tag("tcp")
                                Text("udp").tag("udp")
                            }
                            .labelsHidden()
                            .frame(width: 78)

                            Spacer()

                            removeButton {
                                draft.ports.removeAll { $0.id == port.id }
                                if draft.ports.isEmpty {
                                    draft.ports.append(DraftPort())
                                }
                            }
                        }
                    }
                    addButton {
                        draft.ports.append(DraftPort())
                    }
                }
            }

            PanelRow("Volumes") {
                VStack(spacing: 6) {
                    ForEach($draft.volumes) { $volume in
                        HStack(spacing: 6) {
                            TextField("host path or volume", text: $volume.source)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                            Button {
                                if let path = chooseDirectory() {
                                    volume.source = path
                                }
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("Choose folder")
                            Text("->")
                                .foregroundStyle(.secondary)
                            TextField("/container/path", text: $volume.target)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                            Toggle("ro", isOn: $volume.readOnly)
                                .toggleStyle(.checkbox)
                                .fixedSize()
                            removeButton {
                                draft.volumes.removeAll { $0.id == volume.id }
                            }
                        }
                    }
                    addButton {
                        draft.volumes.append(DraftVolume())
                    }
                }
            }

            PanelRow("Environment") {
                TextField("POSTGRES_PASSWORD=secret\nPOSTGRES_DB=app", text: $draft.environmentText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(3...8)
            }

            if variant == .compose {
                PanelRow("Network") {
                    HStack {
                        TextField("networks", text: $draft.networksText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        TextField("depends on", text: $draft.dependsText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            } else {
                PanelRow("Network") {
                    Picker("", selection: $draft.networkChoice) {
                        Text("Default").tag("")
                        Text("Host").tag("host")
                        Text("Bridge").tag("bridge")
                        ForEach(availableNetworks) { network in
                            Text(network.name).tag(network.name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220, alignment: .leading)
                }
            }

            PanelRow("Command") {
                TextField("Image default", text: $draft.command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            PanelRow("Resources") {
                HStack(spacing: 14) {
                    Stepper("\(draft.cpus) CPU", value: $draft.cpus, in: 1...16)
                        .frame(width: 130, alignment: .leading)
                    Stepper("\(draft.memoryGB.formatted(.number.precision(.fractionLength(1)))) GB", value: $draft.memoryGB, in: 0.5...64, step: 0.5)
                        .frame(width: 160, alignment: .leading)
                }
            }

            PanelRow("Options") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        Picker("Restart", selection: $draft.restartPolicy) {
                            ForEach(RestartPolicy.allCases) { policy in
                                Text(policy.displayName).tag(policy)
                            }
                        }
                        .frame(width: 210)

                        Toggle("Remove when stopped", isOn: $draft.removeAfterStop)
                            .toggleStyle(.switch)

                        Toggle("Forward SSH agent", isOn: $draft.sshAgent)
                            .toggleStyle(.switch)
                    }

                    if variant == .compose {
                        Toggle("Has healthcheck", isOn: $draft.healthcheck)
                            .toggleStyle(.checkbox)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.16))
        }
    }

    private func addButton(_ action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button(action: action) {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.blue)
            .help("Add")
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle.fill")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.red)
        .help("Remove")
    }

    private func chooseDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

private struct PanelRow<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
                .padding(.top, 5)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var commaSeparated: [String] {
        split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }
}

#Preview {
    let vm = ContainerViewModel()
    CreateContainerPanelView(viewModel: vm, composeManager: ComposeManager(runtime: vm.runtime))
}
