import SwiftUI

@main
struct CapsuleApp: App {
    @StateObject private var viewModel = ContainerViewModel()
    @StateObject private var composeManager: ComposeManager
    @StateObject private var restartDaemon: RestartDaemon
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let vm = ContainerViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _composeManager = StateObject(wrappedValue: ComposeManager(runtime: vm.runtime))
        _restartDaemon = StateObject(wrappedValue: RestartDaemon(runtime: vm.runtime))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, composeManager: composeManager)
                .onAppear {
                    appDelegate.viewModel = viewModel
                    restartDaemon.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Container...") {
                    // Trigger new container sheet
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        // Native Settings window (⌘,) — opened from the app menu, like OrbStack.
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: ContainerViewModel?

    func applicationWillTerminate(_ notification: Notification) {
        // Stop container system if auto-start is enabled
        if UserDefaults.standard.bool(forKey: "autoStartRuntime") {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "/usr/local/bin/container system stop"]

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("Failed to stop container system: \(error)")
            }
        }
    }
}

// MARK: - Content View (three-column: sidebar | list | detail)

struct ContentView: View {
    @ObservedObject var viewModel: ContainerViewModel
    @ObservedObject var composeManager: ComposeManager

    @State private var selectedTab: String? = "containers"
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // Per-tab selection (lifted here so both the content and detail columns can read it)
    @State private var containerSel: ContainerListSelection?
    @State private var imageSel: ContainerCLI.ImageInfo?
    @State private var volumeSel: ContainerCLI.VolumeInfo?
    @State private var networkSel: ContainerCLI.NetworkInfo?
    @State private var machineSel: ContainerCLI.MachineInfo?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 260, ideal: 340, max: 520)
        } detail: {
            detailColumn
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedTab) {
                Section("Docker") {
                    Label("Containers", systemImage: "cube.fill").tag("containers")
                    Label("Images", systemImage: "photo.stack.fill").tag("images")
                    Label("Volumes", systemImage: "externaldrive.fill").tag("volumes")
                    Label("Networks", systemImage: "network").tag("networks")
                }

                Section("Linux") {
                    Label("Machines", systemImage: "desktopcomputer").tag("machines")
                }
            }
            .listStyle(.sidebar)

            RuntimeStatusView(viewModel: viewModel)
        }
    }

    // MARK: - Content column (the middle list)

    @ViewBuilder
    private var contentColumn: some View {
        switch selectedTab {
        case "containers":
            ContainersListColumn(viewModel: viewModel, composeManager: composeManager, selection: $containerSel)
        case "images":
            ImagesListColumn(viewModel: viewModel, selection: $imageSel)
        case "volumes":
            VolumesListColumn(viewModel: viewModel, selection: $volumeSel)
        case "networks":
            NetworksListColumn(viewModel: viewModel, selection: $networkSel)
        case "machines":
            MachinesListColumn(viewModel: viewModel, selection: $machineSel)
        default:
            Text("Select a section").foregroundStyle(.secondary)
        }
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detailColumn: some View {
        switch selectedTab {
        case "containers":
            containerDetail
        case "images":
            if let image = imageSel {
                ImageDetailPanel(image: image, viewModel: viewModel)
            } else {
                NoSelectionView(icon: "photo.stack", message: "Select an image to view details")
            }
        case "volumes":
            if let volume = volumeSel {
                VolumeDetailPanel(volume: volume)
            } else {
                NoSelectionView(icon: "externaldrive", message: "Select a volume to view details")
            }
        case "networks":
            if let network = networkSel {
                NetworkDetailPanel(network: network)
            } else {
                NoSelectionView(icon: "network", message: "Select a network to view details")
            }
        case "machines":
            if let machine = machineSel {
                MachineDetailPanel(machine: machine, viewModel: viewModel)
            } else {
                NoSelectionView(icon: "desktopcomputer", message: "Select a machine to view details")
            }
        default:
            NoSelectionView(icon: "cube", message: "No Selection")
        }
    }

    @ViewBuilder
    private var containerDetail: some View {
        switch containerSel {
        case .container(let id):
            if let container = viewModel.containers.first(where: { $0.id == id }) {
                ContainerDetailPanel(container: container, viewModel: viewModel)
            } else {
                NoSelectionView(icon: "cube", message: "Select a container to view details")
            }
        case .project(let id):
            if let project = composeManager.projects.first(where: { $0.id == id }) {
                ProjectDetailPanel(project: project, composeManager: composeManager)
            } else {
                NoSelectionView(icon: "cube", message: "Select a container to view details")
            }
        case nil:
            NoSelectionView(icon: "cube", message: "Select a container to view details")
        }
    }
}

// MARK: - No Selection placeholder
struct NoSelectionView: View {
    var icon: String = "cube"
    var message: String = "No Selection"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Selection")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Settings (native ⌘, window)

struct SettingsView: View {
    @ObservedObject var viewModel: ContainerViewModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            SystemSettingsView()
                .tabItem { Label("System", systemImage: "cpu") }

            LanguageSettingsView()
                .tabItem { Label("Language", systemImage: "globe") }
        }
        .frame(width: 520, height: 360)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("autoStartRuntime") private var autoStartRuntime = false
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval = 2.0
    @AppStorage("externalTerminalApp") private var externalTerminalApp = "Terminal"

    var body: some View {
        Form {
            Section {
                Toggle("Start/Stop Container Runtime with Capsule", isOn: $autoStartRuntime)
                    .toggleStyle(.switch)
                Text("When enabled, Capsule automatically starts the container system on launch and stops it when you quit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Runtime")
            }

            Section {
                HStack {
                    Text("Refresh Interval")
                    Spacer()
                    Text("\(Int(autoRefreshInterval))s").foregroundStyle(.secondary)
                }
                Slider(value: $autoRefreshInterval, in: 1...10, step: 1)
                Text("How often to refresh status (1–10 seconds).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Auto Refresh")
            }

            Section {
                Picker("External Terminal", selection: $externalTerminalApp) {
                    Text("Terminal").tag("Terminal")
                    Text("iTerm").tag("iTerm")
                }
                Text("Used by “Open in Terminal”. The in-app terminal is always available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Terminal")
            }
        }
        .formStyle(.grouped)
    }
}

struct SystemSettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Container CLI")
                    Spacer()
                    if isContainerInstalled() {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Found", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                if !isContainerInstalled() {
                    Text("The Apple container CLI is required. Install it with: brew install container")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("System")
            }
        }
        .formStyle(.grouped)
    }

    private func isContainerInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/usr/local/bin/container")
    }
}

struct LanguageSettingsView: View {
    /// Empty string means "follow the system language".
    @AppStorage("appLanguage") private var appLanguage = ""

    private let languages: [(code: String, name: String)] = [
        ("", "System"),
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("ja", "日本語")
    ]

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $appLanguage) {
                    ForEach(languages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .onChange(of: appLanguage) { _, newValue in
                    if newValue.isEmpty {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                    }
                }
                Text("Changing the language takes effect after restarting Capsule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Language")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Runtime Status View

struct RuntimeStatusView: View {
    @ObservedObject var viewModel: ContainerViewModel
    @State private var isStarting = false
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(cardBackground)
                        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 8 : 4, y: isHovered ? 3 : 2)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Container Runtime")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                        }

                        if let version = runtimeVersion {
                            Text(version)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        if !viewModel.isRuntimeBootstrapped {
                            Button(action: startRuntime) {
                                HStack(spacing: 6) {
                                    if isStarting {
                                        ProgressView()
                                            .controlSize(.mini)
                                            .scaleEffect(0.8)
                                        Text("Starting...")
                                            .font(.system(size: 11))
                                    } else {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 9))
                                        Text("Start Runtime")
                                            .font(.system(size: 11))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                            .disabled(isStarting)
                            .padding(.top, 2)
                        }
                    }
                    .padding(12)
                }
                .frame(height: viewModel.isRuntimeBootstrapped ? 72 : 106)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        viewModel.isRuntimeBootstrapped ? .green : .red
    }

    private var statusText: String {
        viewModel.isRuntimeBootstrapped ? NSLocalizedString("Running", comment: "") : NSLocalizedString("Not Started", comment: "")
    }

    private var cardBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var runtimeVersion: String? {
        guard viewModel.isRuntimeBootstrapped else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "/usr/local/bin/container version 2>/dev/null | head -n 1 || echo 'Unknown'"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if let data = try pipe.fileHandleForReading.readToEnd(),
               let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                return output
            }
        } catch {
            return nil
        }

        return nil
    }

    private func startRuntime() {
        Task {
            isStarting = true

            let checkProcess = Process()
            checkProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
            checkProcess.arguments = ["-c", "/usr/local/bin/container system status 2>&1 | grep 'status' | grep -q 'running'"]

            do {
                try checkProcess.run()
                checkProcess.waitUntilExit()

                if checkProcess.terminationStatus != 0 {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    process.arguments = ["-c", "/usr/local/bin/container system start"]
                    try process.run()
                    process.waitUntilExit()

                    try await Task.sleep(for: .seconds(2))
                }
            } catch {
                print("Failed to start container system: \(error)")
            }

            await viewModel.initializeRuntime()
            isStarting = false
        }
    }
}

#Preview {
    let viewModel = ContainerViewModel()
    ContentView(
        viewModel: viewModel,
        composeManager: ComposeManager(runtime: viewModel.runtime)
    )
    .frame(width: 1100, height: 700)
}
