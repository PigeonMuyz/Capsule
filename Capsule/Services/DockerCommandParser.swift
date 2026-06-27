import Foundation

/// Parse Docker commands and convert them to Container CLI commands
struct DockerCommandParser {

    /// Parse a docker run command into a ContainerSpec
    static func parseDockerRun(_ command: String) throws -> ContainerSpec {
        // Normalize the command: remove line continuations and extra whitespace
        let normalized = command
            .replacingOccurrences(of: "\\\n", with: " ")
            .replacingOccurrences(of: "\\\r\n", with: " ")

        var args = ShellCommandTokenizer.split(normalized)

        guard args.first == "docker" && args.count > 1 && args[1] == "run" else {
            throw ParseError.invalidCommand
        }

        args.removeFirst(2) // Remove "docker run"

        var name: String?
        var image: String = ""
        var ports: [String] = []
        var volumes: [String] = []
        var env: [String: String] = [:]
        var cpus: Int = 2
        var memoryGB: Int = 2
        var command: [String] = []
        var removeAfterStop = false
        var platform: String?
        var network: String?
        var workdir = "/"
        var restartPolicy: RestartPolicy = .no
        var envFiles: [String] = []
        var entrypoint: String?
        var user: String?
        var labels: [String] = []
        var ulimits: [String] = []
        var dnsServers: [String] = []
        var dnsSearchDomains: [String] = []
        var dnsOptions: [String] = []
        var tmpfs: [String] = []
        var shmSize: String?
        var capAdd: [String] = []
        var capDrop: [String] = []
        var devices: [String] = []
        var sysctls: [String] = []
        var interactive = false
        var tty = false

        var i = 0
        while i < args.count {
            let arg = args[i]

            if let value = value(afterPrefix: "--restart=", in: arg) {
                restartPolicy = RestartPolicy(rawValue: value) ?? .no
                i += 1
                continue
            }
            if let value = value(afterPrefix: "--name=", in: arg) {
                name = value
                i += 1
                continue
            }
            if let value = value(afterPrefix: "--env=", in: arg), let (key, value) = parseEnv(value) {
                env[key] = value
                i += 1
                continue
            }
            if let value = value(afterPrefix: "--publish=", in: arg) {
                ports.append(value)
                i += 1
                continue
            }
            if let value = value(afterPrefix: "--volume=", in: arg) {
                volumes.append(value)
                i += 1
                continue
            }

            switch arg {
            case "--name":
                i += 1
                name = args[i]

            case "-p", "--publish":
                i += 1
                ports.append(args[i])

            case "-v", "--volume":
                i += 1
                volumes.append(args[i])

            case "-e", "--env":
                i += 1
                if let (key, value) = parseEnv(args[i]) {
                    env[key] = value
                }

            case "--env-file":
                i += 1
                envFiles.append(args[i])

            case "--cpus":
                i += 1
                cpus = Int(args[i]) ?? 2

            case "-m", "--memory":
                i += 1
                memoryGB = parseMemory(args[i])

            case "--platform":
                i += 1
                platform = args[i]

            case "--network":
                i += 1
                network = args[i]

            case "-w", "--workdir":
                i += 1
                workdir = args[i]

            case "--restart":
                i += 1
                restartPolicy = RestartPolicy(rawValue: args[i]) ?? .no

            case "--entrypoint":
                i += 1
                entrypoint = args[i]

            case "-u", "--user":
                i += 1
                user = args[i]

            case "--label":
                i += 1
                labels.append(args[i])

            case "--ulimit":
                i += 1
                ulimits.append(args[i])

            case "--dns":
                i += 1
                dnsServers.append(args[i])

            case "--dns-search":
                i += 1
                dnsSearchDomains.append(args[i])

            case "--dns-option":
                i += 1
                dnsOptions.append(args[i])

            case "--tmpfs":
                i += 1
                tmpfs.append(args[i])

            case "--shm-size":
                i += 1
                shmSize = args[i]

            case "--cap-add":
                i += 1
                capAdd.append(args[i])

            case "--cap-drop":
                i += 1
                capDrop.append(args[i])

            case "--device":
                i += 1
                devices.append(args[i])

            case "--sysctl":
                i += 1
                sysctls.append(args[i])

            case "--rm":
                removeAfterStop = true

            case "-i", "--interactive":
                interactive = true

            case "-t", "--tty":
                tty = true

            case "-it", "-ti":
                interactive = true
                tty = true

            case "-d", "--detach":
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

        var spec = ContainerSpec(
            name: containerName,
            image: image,
            cpus: cpus,
            memoryBytes: memoryBytes,
            command: command,
            workingDirectory: workdir
        )
        spec.environment = env
        spec.envFiles = envFiles
        spec.publishedPorts = ports
        spec.volumeBinds = volumes
        spec.network = network
        spec.platform = platform
        spec.removeAfterStop = removeAfterStop
        spec.restartPolicy = restartPolicy
        spec.entrypoint = entrypoint
        spec.user = user
        spec.labels = labels
        spec.ulimits = ulimits
        spec.dnsServers = dnsServers
        spec.dnsSearchDomains = dnsSearchDomains
        spec.dnsOptions = dnsOptions
        spec.tmpfs = tmpfs
        spec.shmSize = shmSize
        spec.capAdd = capAdd
        spec.capDrop = capDrop
        spec.interactive = interactive
        spec.tty = tty

        // Note: --device and --sysctl are stored but not directly supported by Container CLI
        // They would need special handling in RuntimeCore

        return spec
    }

    private static func value(afterPrefix prefix: String, in argument: String) -> String? {
        guard argument.hasPrefix(prefix) else { return nil }
        return String(argument.dropFirst(prefix.count))
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
                return String(localized: "Invalid docker run command")
            case .missingImage:
                return String(localized: "No image specified")
            }
        }
    }
}
