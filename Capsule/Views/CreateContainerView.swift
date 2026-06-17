import SwiftUI

/// View for creating a new container
struct CreateContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ContainerViewModel

    @State private var name = ""
    @State private var image = "alpine:latest"
    @State private var cpus = 2
    @State private var memoryGB = 2.0
    @State private var command = "/bin/sh"
    @State private var workingDirectory = "/"
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Container Information") {
                    TextField("Name", text: $name, prompt: Text("my-container"))
                        .textFieldStyle(.roundedBorder)

                    TextField("Image", text: $image, prompt: Text("alpine:latest"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .help("Docker image reference (e.g., nginx:alpine, ubuntu:22.04)")
                }

                Section("Resources") {
                    HStack {
                        Text("CPUs")
                        Spacer()
                        Stepper("\(cpus)", value: $cpus, in: 1...8)
                            .frame(width: 120)
                    }

                    HStack {
                        Text("Memory")
                        Spacer()
                        Stepper(String(format: "%.1f GB", memoryGB), value: $memoryGB, in: 0.5...16, step: 0.5)
                            .frame(width: 140)
                    }
                }

                Section("Configuration") {
                    TextField("Command", text: $command, prompt: Text("/bin/sh"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .help("Command to run when container starts")

                    TextField("Working Directory", text: $workingDirectory, prompt: Text("/"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                if let errorMessage = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Container")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createContainer()
                    }
                    .disabled(!isValid || isCreating)
                }
            }
            .frame(width: 500, height: 450)
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !image.trimmingCharacters(in: .whitespaces).isEmpty &&
        !command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func createContainer() {
        errorMessage = nil
        isCreating = true

        Task {
            do {
                let spec = ContainerSpec(
                    name: name.trimmingCharacters(in: .whitespaces),
                    image: image.trimmingCharacters(in: .whitespaces),
                    cpus: cpus,
                    memoryBytes: UInt64(memoryGB * 1024 * 1024 * 1024),
                    rootfsSizeBytes: 10 * 1024 * 1024 * 1024, // 10GB default
                    command: parseCommand(command),
                    workingDirectory: workingDirectory.trimmingCharacters(in: .whitespaces)
                )

                await viewModel.createContainer(spec: spec)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }

    private func parseCommand(_ command: String) -> [String] {
        // Simple command parsing - split by spaces
        // For MVP, we expect simple commands like "/bin/sh" or "/bin/sh -c echo hello"
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return ["/bin/sh"]
        }
        return trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }
}

#Preview {
    CreateContainerView(viewModel: ContainerViewModel())
}
