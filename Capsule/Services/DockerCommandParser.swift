import Foundation

/// Parse Docker commands and convert them to Container CLI commands
struct DockerCommandParser {

    /// Parse a docker run command into a ContainerSpec
    static func parseDockerRun(_ command: String) throws -> ContainerSpec {
        // Remove "docker run" prefix
        var args = command.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard args.first == "docker" && args.count > 1 && args[1] == "run" else {
            throw ParseError.invalidCommand
        }

        args.removeFirst(2) // Remove "docker run"

        var name: String?
        var image: String = ""
        var ports: [(host: Int, container: Int)] = []
        var volumes: [String] = []
        var env: [String: String] = [:]
        var cpus: Int = 2
        var memoryGB: Int = 2
        var command: [String] = []

        var i = 0
        while i < args.count {
            let arg = args[i]

            switch arg {
            case "--name":
                i += 1
                name = args[i]

            case "-p", "--publish":
                i += 1
                if let portPair = parsePort(args[i]) {
                    ports.append(portPair)
                }

            case "-v", "--volume":
                i += 1
                volumes.append(args[i])

            case "-e", "--env":
                i += 1
                if let (key, value) = parseEnv(args[i]) {
                    env[key] = value
                }

            case "--cpus":
                i += 1
                cpus = Int(args[i]) ?? 2

            case "-m", "--memory":
                i += 1
                memoryGB = parseMemory(args[i])

            case "-d", "--detach", "--rm", "-it", "-i", "-t":
                // Flags without values, skip
                break

            default:
                // First non-flag argument is the image
                if !arg.hasPrefix("-") {
                    if image.isEmpty {
                        image = arg
                    } else {
                        // Rest are command arguments
                        command.append(arg)
                    }
                }
            }

            i += 1
        }

        guard !image.isEmpty else {
            throw ParseError.missingImage
        }

        let containerName = name ?? "container-\(UUID().uuidString.prefix(8))"
        let memoryBytes = UInt64(memoryGB) * 1024 * 1024 * 1024

        return ContainerSpec(
            name: containerName,
            image: image,
            cpus: cpus,
            memoryBytes: memoryBytes,
            command: command
        )
    }

    private static func parsePort(_ portString: String) -> (host: Int, container: Int)? {
        let parts = portString.split(separator: ":")
        guard parts.count >= 2,
              let host = Int(parts[0]),
              let container = Int(parts[1]) else {
            return nil
        }
        return (host, container)
    }

    private static func parseEnv(_ envString: String) -> (String, String)? {
        let parts = envString.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private static func parseMemory(_ memString: String) -> Int {
        var value = memString
        var multiplier = 1

        if value.hasSuffix("g") || value.hasSuffix("G") {
            value.removeLast()
            multiplier = 1
        } else if value.hasSuffix("m") || value.hasSuffix("M") {
            value.removeLast()
            multiplier = 1024
        }

        return (Int(value) ?? 2) * multiplier
    }

    enum ParseError: Error, LocalizedError {
        case invalidCommand
        case missingImage

        var errorDescription: String? {
            switch self {
            case .invalidCommand:
                return "Invalid docker run command"
            case .missingImage:
                return "No image specified"
            }
        }
    }
}
