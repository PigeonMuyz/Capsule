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
        .columnToolbar(title: "Machines", addHelp: "Create Machine") { showingCreateSheet = true }
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
                Circle()
                    .fill(machine.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.teal)

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

// MARK: - Machine Detail Panel

struct MachineDetailPanel: View {
    let machine: ContainerCLI.MachineInfo
    @ObservedObject var viewModel: ContainerViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                Text(machine.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if machine.isRunning {
                    Button(action: { Task { try? await viewModel.runtime.stopMachine(name: machine.name) } }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: { Task { try? await viewModel.runtime.startMachine(name: machine.name) } }) {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(action: openShell) {
                    Label("Open Shell", systemImage: "terminal")
                }
                .buttonStyle(.bordered)

                Menu {
                    Button("Delete", role: .destructive) {
                        Task { try? await viewModel.runtime.deleteMachine(name: machine.name) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    InfoSection(title: "General") {
                        InfoRow(label: "Name", value: machine.name)
                        InfoRow(label: "State", value: machine.state)
                        if let ip = machine.ipAddress {
                            InfoRow(label: "IP", value: ip)
                        }
                    }

                    InfoSection(title: "Resources") {
                        InfoRow(label: "CPUs", value: "\(machine.cpus)")
                        InfoRow(label: "Memory", value: formatMemory(machine.memoryBytes))
                    }
                }
                .padding()
            }
        }
    }

    private func formatMemory(_ bytes: Int) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
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
