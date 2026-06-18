import SwiftUI
import SwiftTerm

/// In-app interactive terminal for a container, backed by SwiftTerm's
/// LocalProcessTerminalView running `container exec -it <id> sh` in a PTY.
struct ContainerTerminalRepresentable: NSViewRepresentable {
    let containerID: String

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.startProcess(
            executable: "/usr/local/bin/container",
            args: ["exec", "-it", containerID, "sh"],
            environment: nil
        )
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}

/// Opens an interactive shell into a container/machine in the user's preferred
/// external terminal application (configurable in Settings).
enum ExternalTerminal {
    static func open(command: String) {
        let app = UserDefaults.standard.string(forKey: "externalTerminalApp") ?? "Terminal"
        let script: String
        switch app {
        case "iTerm":
            script = """
            tell application "iTerm"
              activate
              create window with default profile
              tell current session of current window to write text "\(command)"
            end tell
            """
        default:
            script = "tell application \"Terminal\"\nactivate\ndo script \"\(command)\"\nend tell"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}
