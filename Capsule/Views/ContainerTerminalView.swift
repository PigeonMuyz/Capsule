import SwiftUI

/// Terminal view for container shell access
struct ContainerTerminalView: View {
    let containerID: String
    let containerName: String

    @State private var output: [String] = []
    @State private var command: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Terminal output
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(output.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: output.count) { _, _ in
                        if let last = output.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            // Command input
            HStack {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                TextField("Enter command...", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        executeCommand()
                    }

                Button(action: executeCommand) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(command.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .onAppear {
            output.append("# Connected to \(containerName)")
            output.append("# Type commands to execute in the container")
            output.append("# Note: This is a simulated terminal. Real shell integration coming soon.")
            output.append("")
        }
    }

    private func executeCommand() {
        guard !command.isEmpty else { return }

        // Add command to output
        output.append("$ \(command)")

        // Simulate command execution
        Task {
            let result = await simulateCommand(command)
            output.append(result)
            output.append("")
        }

        command = ""
    }

    private func simulateCommand(_ cmd: String) async -> String {
        // Simulate delay
        try? await Task.sleep(for: .milliseconds(200))

        // Simulate common commands
        switch cmd.trimmingCharacters(in: .whitespaces) {
        case "ls", "ls -la":
            return """
            bin  boot  dev  etc  home  lib  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var
            """
        case "pwd":
            return "/root"
        case "whoami":
            return "root"
        case "ps", "ps aux":
            return """
            PID   USER     TIME  COMMAND
            1     root      0:00 /bin/sh
            """
        case let cmd where cmd.hasPrefix("echo"):
            return String(cmd.dropFirst(5))
        case "help":
            return """
            Simulated terminal commands:
            - ls, pwd, whoami, ps, echo
            - Real shell integration coming soon
            """
        default:
            return "Command not found (simulated terminal)"
        }
    }
}

#Preview {
    ContainerTerminalView(containerID: "test", containerName: "test-container")
        .frame(width: 700, height: 500)
}
