import SwiftUI

/// Middle column of the Machines view (Linux section): the list of container
/// machines — full loginable Linux VMs, distinct from containers.
struct MachinesListColumn: View {
    @ObservedObject var viewModel: ContainerViewModel
    @Binding var selection: ContainerCLI.MachineInfo?

    @State private var machines: [ContainerCLI.MachineInfo] = []
    @State private var showingCreateSheet = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && machines.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if machines.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(machines) { machine in
                            MachineRow(
                                machine: machine,
                                isSelected: selection?.id == machine.id,
                                onSelect: { selection = machine }
                            )
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationTitle("Machines")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingCreateSheet = true }) {
                    Label("Create", systemImage: "plus")
                }
                .help("Create Machine")
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateMachineView { name, image, cpus, memory, platform in
                Task { await createMachine(name: name, image: image, cpus: cpus, memory: memory, platform: platform) }
            }
        }
        .task {
            while !Task.isCancelled {
                await loadMachines()
                let i = UserDefaults.standard.double(forKey: "autoRefreshInterval")
                try? await Task.sleep(for: .seconds(max(i > 0 ? i : 2.0, 5)))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Machines")
                .font(.title3)
                .fontWeight(.semibold)

            Text("A machine is a full Linux VM you can log into")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showingCreateSheet = true }) {
                Label("Create Machine", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func loadMachines() async {
        isLoading = true
        do {
            machines = try await viewModel.runtime.listMachines()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func createMachine(name: String, image: String, cpus: Int?, memory: Double?, platform: String?) async {
        do {
            try await viewModel.runtime.createMachine(name: name, image: image, cpus: cpus, memoryGB: memory, platform: platform)
            await loadMachines()
        } catch {
            errorMessage = "Failed to create machine: \(error.localizedDescription)"
        }
    }
}

// MARK: - Machine Row

struct MachineRow: View {
    let machine: ContainerCLI.MachineInfo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 状态指示灯
                Circle()
                    .fill(machine.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(machine.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(machine.state)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Machine Detail Panel (Picker-style tabs)

struct MachineDetailPanel: View {
    let machine: ContainerCLI.MachineInfo?
    @ObservedObject var viewModel: ContainerViewModel

    @State private var selectedTab: DetailTab = .overview

    enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case console = "Console"
        case logs = "Logs"

        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let machine = machine {
                switch selectedTab {
                case .overview:
                    MachineOverviewView(machine: machine, viewModel: viewModel)
                case .console:
                    MachineConsoleView(machine: machine)
                case .logs:
                    MachineLogsView(machine: machine, viewModel: viewModel)
                }
            } else {
                NoSelectionView(icon: "desktopcomputer", message: "Select a machine to view details")
            }
        }
        .navigationTitle(machine?.name ?? "Machine")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .disabled(machine == nil)
            }
        }
    }
}

// MARK: - Overview View

struct MachineOverviewView: View {
    let machine: ContainerCLI.MachineInfo
    @ObservedObject var viewModel: ContainerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Actions
                InfoSection(title: "Controls") {
                    HStack(spacing: 12) {
                        if machine.isRunning {
                            Button(action: stopMachine) {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button(action: startMachine) {
                                Label("Start", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button(action: openShell) {
                            Label("Open Shell", systemImage: "terminal")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!machine.isRunning)

                        Spacer()

                        Button(role: .destructive, action: deleteMachine) {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // General
                InfoSection(title: "General") {
                    InfoRow(label: "Name", value: machine.name)
                    Divider()
                    InfoRow(label: "State", value: machine.state)
                    if let ip = machine.ipAddress {
                        Divider()
                        InfoRow(label: "IP Address", value: ip)
                    }
                }

                // Resources
                InfoSection(title: "Resources") {
                    InfoRow(label: "CPUs", value: "\(machine.cpus)")
                    Divider()
                    InfoRow(label: "Memory", value: formatMemory(machine.memoryBytes))
                }

                Spacer(minLength: 16)
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func formatMemory(_ bytes: Int) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func startMachine() {
        Task { try? await viewModel.runtime.startMachine(name: machine.name) }
    }

    private func stopMachine() {
        Task { try? await viewModel.runtime.stopMachine(name: machine.name) }
    }

    private func deleteMachine() {
        Task { try? await viewModel.runtime.deleteMachine(name: machine.name) }
    }

    /// Open an interactive shell into the machine in Terminal.app.
    private func openShell() {
        let command = "/usr/local/bin/container machine run -n \(machine.name)"
        let script = "tell application \"Terminal\" to do script \"\(command)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}

// MARK: - Console View

struct MachineConsoleView: View {
    let machine: ContainerCLI.MachineInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Interactive Shell")
                .font(.headline)

            Text("Click the button below to open an interactive shell in Terminal.app")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: openShell) {
                Label("Open Terminal", systemImage: "terminal.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!machine.isRunning)

            if !machine.isRunning {
                Text("Machine must be running to access console")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }

    private func openShell() {
        let command = "/usr/local/bin/container machine run -n \(machine.name)"
        let script = "tell application \"Terminal\" to do script \"\(command)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}

// MARK: - Logs View

struct MachineLogsView: View {
    let machine: ContainerCLI.MachineInfo
    @ObservedObject var viewModel: ContainerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Machine Logs")
                .font(.headline)

            Text("Coming soon: View machine startup and runtime logs using container machine logs")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}

// MARK: - Create Machine View

struct CreateMachineView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var image = "alpine:3.22"
    @State private var cpus = 2
    @State private var memoryGB = 2.0
    @State private var platform = "auto"
    @State private var isCreating = false

    /// (name, image, cpus, memoryGB, platform)
    let onCreate: (String, String, Int?, Double?, String?) -> Void

    private let platforms = ["auto", "linux/arm64", "linux/amd64"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Machine") {
                    TextField("Name", text: $name, prompt: Text("my-machine"))
                        .textFieldStyle(.roundedBorder)
                    TextField("Image", text: $image, prompt: Text("alpine:3.22"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Picker("Platform", selection: $platform) {
                        ForEach(platforms, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Resources") {
                    HStack {
                        Text("CPUs")
                        Spacer()
                        Stepper("\(cpus)", value: $cpus, in: 1...16).frame(width: 120)
                    }
                    HStack {
                        Text("Memory")
                        Spacer()
                        Stepper(String(format: "%.0f GB", memoryGB), value: $memoryGB, in: 1...32, step: 1)
                            .frame(width: 140)
                    }
                }

                if isCreating {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Creating machine…")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Machine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        isCreating = true
                        onCreate(name, image, cpus, memoryGB, platform)
                        dismiss()
                    }
                    .disabled(name.isEmpty || image.isEmpty || isCreating)
                }
            }
            .frame(width: 500, height: 360)
        }
    }
}
