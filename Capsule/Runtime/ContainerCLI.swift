import Foundation
import OSLog

private let logger = Logger(subsystem: "io.github.pigeonmuyz.capsule", category: "cli")

/// Wrapper for Apple `container` CLI tool
/// Provides Swift-friendly interface to system container operations
actor ContainerCLI {

    // MARK: - Container List

    struct ContainerInfo: Codable {
        let id: String
        let configuration: Configuration
        let status: Status

        struct Configuration: Codable {
            let id: String
            let image: Image
            let platform: Platform
            let resources: Resources
            let creationDate: String?

            struct Image: Codable {
                let reference: String
            }

            struct Platform: Codable {
                let architecture: String
                let os: String
            }

            struct Resources: Codable {
                let cpus: Int
                let memoryInBytes: Int
            }
        }

        struct Status: Codable {
            let state: String
            let startedDate: String?
            let networks: [Network]?

            struct Network: Codable {
                let ipv4Address: String?
            }
        }
    }

    /// List all containers in the system
    func listContainers() async throws -> [ContainerInfo] {
        logger.info("Listing containers via CLI")

        let output = try await runCommand(["list", "--all", "--format", "json"])

        guard let data = output.data(using: .utf8) else {
            throw CLIError.invalidOutput("Failed to convert output to data")
        }

        do {
            let containers = try JSONDecoder().decode([ContainerInfo].self, from: data)
            logger.info("Found \(containers.count) containers")
            return containers
        } catch {
            logger.error("Failed to parse container list: \(error)")
            throw CLIError.parseError(error.localizedDescription)
        }
    }

    // MARK: - Container Operations

    /// Start a container by ID
    func startContainer(id: String) async throws {
        logger.info("Starting container: \(id)")
        _ = try await runCommand(["start", id])
        logger.info("Container started: \(id)")
    }

    /// Stop a container by ID
    func stopContainer(id: String) async throws {
        logger.info("Stopping container: \(id)")
        _ = try await runCommand(["stop", id])
        logger.info("Container stopped: \(id)")
    }

    /// Delete a container by ID
    func deleteContainer(id: String) async throws {
        logger.info("Deleting container: \(id)")
        _ = try await runCommand(["rm", id])
        logger.info("Container deleted: \(id)")
    }

    /// Create a new container
    func createContainer(
        name: String,
        image: String,
        cpus: Int,
        memoryMB: Int,
        command: [String]? = nil,
        environment: [String: String] = [:],
        envFiles: [String] = [],
        ports: [String] = [],
        sockets: [String] = [],
        network: String? = nil,
        platform: String? = nil,
        volumes: [String] = [],
        workingDirectory: String? = nil,
        entrypoint: String? = nil,
        user: String? = nil,
        uid: String? = nil,
        gid: String? = nil,
        labels: [String] = [],
        ulimits: [String] = [],
        dnsServers: [String] = [],
        dnsSearchDomains: [String] = [],
        dnsOptions: [String] = [],
        noDNS: Bool = false,
        tmpfs: [String] = [],
        shmSize: String? = nil,
        capAdd: [String] = [],
        capDrop: [String] = [],
        interactive: Bool = false,
        tty: Bool = false,
        sshAgent: Bool = false,
        virtualization: Bool = false,
        rosetta: Bool = false,
        removeAfterStop: Bool = false,
        readOnlyRootfs: Bool = false,
        useInit: Bool = false
    ) async throws -> String {
        logger.info("Creating container: \(name) with image: \(image)")

        var args = [
            "create",
            "--name", name,
            "--cpus", "\(cpus)",
            "--memory", "\(memoryMB)MB"
        ]

        // Flags must precede the image positional argument.
        for (key, value) in environment {
            args.append(contentsOf: ["--env", "\(key)=\(value)"])
        }
        for envFile in envFiles where !envFile.isEmpty {
            args.append(contentsOf: ["--env-file", envFile])
        }
        for port in ports where !port.isEmpty {
            args.append(contentsOf: ["--publish", port])
        }
        for socket in sockets where !socket.isEmpty {
            args.append(contentsOf: ["--publish-socket", socket])
        }
        for volume in volumes where !volume.isEmpty {
            args.append(contentsOf: ["--volume", volume])
        }
        if let network, !network.isEmpty {
            args.append(contentsOf: ["--network", network])
        }
        if let platform, !platform.isEmpty, platform != "auto" {
            args.append(contentsOf: ["--platform", platform])
        }
        if let workingDirectory, !workingDirectory.isEmpty, workingDirectory != "/" {
            args.append(contentsOf: ["--workdir", workingDirectory])
        }
        if let entrypoint, !entrypoint.isEmpty {
            args.append(contentsOf: ["--entrypoint", entrypoint])
        }
        if let user, !user.isEmpty {
            args.append(contentsOf: ["--user", user])
        }
        if let uid, !uid.isEmpty {
            args.append(contentsOf: ["--uid", uid])
        }
        if let gid, !gid.isEmpty {
            args.append(contentsOf: ["--gid", gid])
        }
        for label in labels where !label.isEmpty {
            args.append(contentsOf: ["--label", label])
        }
        for ulimit in ulimits where !ulimit.isEmpty {
            args.append(contentsOf: ["--ulimit", ulimit])
        }
        for dns in dnsServers where !dns.isEmpty {
            args.append(contentsOf: ["--dns", dns])
        }
        for domain in dnsSearchDomains where !domain.isEmpty {
            args.append(contentsOf: ["--dns-search", domain])
        }
        for option in dnsOptions where !option.isEmpty {
            args.append(contentsOf: ["--dns-option", option])
        }
        if noDNS {
            args.append("--no-dns")
        }
        for path in tmpfs where !path.isEmpty {
            args.append(contentsOf: ["--tmpfs", path])
        }
        if let shmSize, !shmSize.isEmpty {
            args.append(contentsOf: ["--shm-size", shmSize])
        }
        for cap in capAdd where !cap.isEmpty {
            args.append(contentsOf: ["--cap-add", cap])
        }
        for cap in capDrop where !cap.isEmpty {
            args.append(contentsOf: ["--cap-drop", cap])
        }
        if interactive {
            args.append("--interactive")
        }
        if tty {
            args.append("--tty")
        }
        if sshAgent {
            args.append("--ssh")
        }
        if virtualization {
            args.append("--virtualization")
        }
        if rosetta {
            args.append("--rosetta")
        }
        if removeAfterStop {
            args.append("--rm")
        }
        if readOnlyRootfs {
            args.append("--read-only")
        }
        if useInit {
            args.append("--init")
        }

        args.append(image)

        if let command = command, !command.isEmpty {
            args.append(contentsOf: command)
        }

        let output = try await runCommand(args)
        let containerID = output.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Container created with ID: \(containerID)")
        return containerID
    }

    // MARK: - Logs

    /// Get container logs
    func getContainerLogs(id: String, tail: Int? = nil) async throws -> String {
        logger.info("Fetching logs for container: \(id)")

        var args = ["logs", id]
        if let tail = tail {
            args.append(contentsOf: ["-n", "\(tail)"])
        }

        let output = try await runCommand(args)
        return output
    }

    /// Stream container logs (returns AsyncStream)
    func streamContainerLogs(id: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    process.arguments = ["-c", "/usr/local/bin/container logs --follow \(id)"]

                    let pipe = Pipe()
                    process.standardOutput = pipe

                    try process.run()

                    let handle = pipe.fileHandleForReading

                    // Read data asynchronously
                    for try await line in handle.bytes.lines {
                        continuation.yield(line)
                    }

                    continuation.finish()
                } catch {
                    logger.error("Failed to stream logs: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Container Inspect

    struct ContainerDetails: Codable {
        let id: String
        let configuration: Configuration
        let status: Status

        struct Configuration: Codable {
            let id: String
            let image: Image
            let initProcess: InitProcess?
            let mounts: [Mount]
            let publishedPorts: [PublishedPort]
            let networks: [Network]
            let platform: Platform?
            let resources: Resources?
            let creationDate: String?

            struct Image: Codable {
                let reference: String
            }

            struct InitProcess: Codable {
                let executable: String?
                let arguments: [String]?
                let environment: [String]?
                let workingDirectory: String?
            }

            struct Mount: Codable, Identifiable {
                var id: String { "\(source)|\(destination)" }
                let source: String
                let destination: String
                let options: [String]?
            }

            struct PublishedPort: Codable, Identifiable {
                var id: String { "\(hostAddress ?? ""):\(hostPort ?? 0):\(containerPort)/\(proto ?? "tcp")" }
                let containerPort: Int
                let count: Int?
                let hostAddress: String?
                let hostPort: Int?
                let proto: String?
            }

            struct Network: Codable, Identifiable {
                var id: String { network }
                let network: String
            }

            struct Platform: Codable {
                let architecture: String
                let os: String
                let variant: String?
            }

            struct Resources: Codable {
                let cpus: Int?
                let memoryInBytes: Int?
            }
        }

        struct Status: Codable {
            let state: String
            let startedDate: String?
        }
    }

    /// Get detailed information about a container
    func inspectContainer(id: String) async throws -> ContainerDetails {
        logger.info("Inspecting container: \(id)")

        let output = try await runCommand(["inspect", id])

        guard let data = output.data(using: .utf8) else {
            throw CLIError.invalidOutput("Failed to convert output to data")
        }

        do {
            if let details = try JSONDecoder().decode([ContainerDetails].self, from: data).first {
                return details
            }
            throw CLIError.invalidOutput("Container inspect returned no records")
        } catch {
            logger.error("Failed to parse container details: \(error)")
            throw CLIError.parseError(error.localizedDescription)
        }
    }

    // MARK: - Files

    struct FileInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let path: String
        let permissions: String
        let owner: String
        let group: String
        let size: Int64
        let modified: String
        let isDirectory: Bool
        let isSymlink: Bool
        let symlinkTarget: String?
    }

    /// List files in a running container using `container exec ls -la`.
    func listFiles(containerID: String, path: String) async throws -> [FileInfo] {
        logger.info("Listing files for container: \(containerID), path: \(path)")
        let output = try await runCommand(["exec", containerID, "ls", "-la", path])
        return output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { parseFileLine(String($0), parentPath: path) }
    }

    /// Delete a file or directory inside a running container.
    func deleteFile(containerID: String, path: String) async throws {
        logger.info("Deleting file in container: \(containerID), path: \(path)")
        _ = try await runCommand(["exec", containerID, "rm", "-rf", path])
    }

    /// Copy a file from a running container to a local destination.
    func copyFileFromContainer(containerID: String, path: String, destination: URL) async throws {
        logger.info("Copying file from container: \(containerID), path: \(path)")
        _ = try await runCommand(["copy", "\(containerID):\(path)", destination.path])
    }

    /// Copy a local file back into a running container.
    func copyFileToContainer(containerID: String, source: URL, path: String) async throws {
        logger.info("Copying local file to container: \(containerID), path: \(path)")
        _ = try await runCommand(["copy", source.path, "\(containerID):\(path)"])
    }

    // MARK: - Images

    struct ImageInfo: Codable, Identifiable {
        let id: String
        let configuration: ImageConfiguration
        let variants: [Variant]?

        struct ImageConfiguration: Codable {
            let name: String
            let creationDate: String?
            let descriptor: Descriptor

            struct Descriptor: Codable {
                let digest: String
                let size: Int64
            }
        }

        struct Variant: Codable {
            let size: Int64
            let digest: String
            let platform: Platform?

            struct Platform: Codable {
                let architecture: String
                let os: String
            }
        }

        // Computed properties for UI
        var repository: String {
            let parts = configuration.name.split(separator: ":")
            return String(parts.first ?? "")
        }

        var tag: String {
            let parts = configuration.name.split(separator: ":")
            return parts.count > 1 ? String(parts[1]) : "latest"
        }

        var digest: String {
            configuration.descriptor.digest
        }

        var size: Int64 {
            // Use the first variant's size (actual image size), not descriptor size (manifest size)
            variants?.first?.size ?? configuration.descriptor.size
        }

        var created: String {
            configuration.creationDate ?? ""
        }

        enum CodingKeys: String, CodingKey {
            case id
            case configuration
            case variants
        }
    }

    /// List all images
    func listImages() async throws -> [ImageInfo] {
        logger.info("Listing images via CLI")

        let output = try await runCommand(["image", "list", "--format", "json"])

        guard let data = output.data(using: .utf8) else {
            throw CLIError.invalidOutput("Failed to convert output to data")
        }

        do {
            let images = try JSONDecoder().decode([ImageInfo].self, from: data)
            logger.info("Found \(images.count) images")
            return images
        } catch {
            logger.error("Failed to parse image list: \(error)")
            throw CLIError.parseError(error.localizedDescription)
        }
    }

    /// Pull an image
    func pullImage(reference: String) async throws {
        logger.info("Pulling image: \(reference)")
        _ = try await runCommand(["image", "pull", reference])
        logger.info("Image pulled: \(reference)")
    }

    /// Delete an image
    func deleteImage(id: String) async throws {
        logger.info("Deleting image: \(id)")
        _ = try await runCommand(["image", "rm", id])
        logger.info("Image deleted: \(id)")
    }

    // MARK: - Volumes

    struct VolumeInfo: Codable, Identifiable {
        var id: String { name }
        let configuration: VolumeConfiguration

        struct VolumeConfiguration: Codable {
            let name: String
            let driver: String
            let source: String?
            let creationDate: String?
            let sizeInBytes: Int64?
        }

        // Computed properties for UI
        var name: String {
            configuration.name
        }

        var mountPoint: String {
            configuration.source ?? ""
        }

        var driver: String {
            configuration.driver
        }

        var createdAt: String? {
            configuration.creationDate
        }

        enum CodingKeys: String, CodingKey {
            case configuration
        }
    }

    /// List all volumes
    func listVolumes() async throws -> [VolumeInfo] {
        logger.info("Listing volumes via CLI")

        let output = try await runCommand(["volume", "list", "--format", "json"])

        guard let data = output.data(using: .utf8) else {
            throw CLIError.invalidOutput("Failed to convert output to data")
        }

        do {
            let volumes = try JSONDecoder().decode([VolumeInfo].self, from: data)
            logger.info("Found \(volumes.count) volumes")
            return volumes
        } catch {
            logger.error("Failed to parse volume list: \(error)")
            throw CLIError.parseError(error.localizedDescription)
        }
    }

    /// Create a volume
    func createVolume(name: String) async throws {
        logger.info("Creating volume: \(name)")
        _ = try await runCommand(["volume", "create", name])
        logger.info("Volume created: \(name)")
    }

    /// Delete a volume
    func deleteVolume(name: String) async throws {
        logger.info("Deleting volume: \(name)")
        _ = try await runCommand(["volume", "rm", name])
        logger.info("Volume deleted: \(name)")
    }

    // MARK: - Networks

    struct NetworkInfo: Codable, Identifiable {
        let id: String
        let configuration: NetworkConfiguration
        let status: NetworkStatus?

        struct NetworkConfiguration: Codable {
            let name: String
            let mode: String
            let plugin: String
            let creationDate: String?
        }

        struct NetworkStatus: Codable {
            let ipv4Gateway: String?
            let ipv4Subnet: String?
            let ipv6Subnet: String?
        }

        // Computed properties for UI
        var name: String {
            configuration.name
        }

        var driver: String {
            configuration.plugin
        }

        var subnet: String? {
            status?.ipv4Subnet
        }

        enum CodingKeys: String, CodingKey {
            case id
            case configuration
            case status
        }
    }

    /// List all networks
    func listNetworks() async throws -> [NetworkInfo] {
        logger.info("Listing networks via CLI")

        let output = try await runCommand(["network", "list", "--format", "json"])

        guard let data = output.data(using: .utf8) else {
            throw CLIError.invalidOutput("Failed to convert output to data")
        }

        do {
            let networks = try JSONDecoder().decode([NetworkInfo].self, from: data)
            logger.info("Found \(networks.count) networks")
            return networks
        } catch {
            logger.error("Failed to parse network list: \(error)")
            throw CLIError.parseError(error.localizedDescription)
        }
    }

    /// Create a network
    func createNetwork(name: String, driver: String = "bridge") async throws {
        logger.info("Creating network: \(name)")
        _ = try await runCommand(["network", "create", "--driver", driver, name])
        logger.info("Network created: \(name)")
    }

    /// Delete a network
    func deleteNetwork(name: String) async throws {
        logger.info("Deleting network: \(name)")
        _ = try await runCommand(["network", "rm", name])
        logger.info("Network deleted: \(name)")
    }

    // MARK: - Machines

    /// A container machine (a full, loginable Linux VM — distinct from a container).
    struct MachineInfo: Codable, Identifiable {
        let configuration: MachineConfiguration
        let status: MachineStatus?

        var id: String { configuration.name }

        struct MachineConfiguration: Codable {
            let name: String
            let cpus: Int?
            let memoryInBytes: Int?
            let creationDate: String?
        }

        struct MachineStatus: Codable {
            let state: String?
            let ipv4Address: String?
        }

        // Computed properties for UI
        var name: String { configuration.name }
        var state: String { status?.state ?? "unknown" }
        var ipAddress: String? { status?.ipv4Address }
        var cpus: Int { configuration.cpus ?? 0 }
        var memoryBytes: Int { configuration.memoryInBytes ?? 0 }
        var isRunning: Bool { state.lowercased() == "running" }
    }

    /// List all container machines.
    func listMachines() async throws -> [MachineInfo] {
        logger.info("Listing machines via CLI")
        let output = try await runCommand(["machine", "list", "--format", "json"])
        guard let data = output.data(using: .utf8) else {
            throw CLIError.invalidOutput("Failed to convert output to data")
        }
        do {
            return try JSONDecoder().decode([MachineInfo].self, from: data)
        } catch {
            // The exact JSON shape may differ across CLI versions; log and degrade
            // gracefully rather than crashing the UI.
            logger.error("Failed to parse machine list: \(error). Raw: \(output)")
            return []
        }
    }

    /// Create (and boot) a new machine from an image.
    func createMachine(name: String, image: String, cpus: Int?, memoryGB: Double?, platform: String?) async throws {
        logger.info("Creating machine: \(name) from \(image)")
        var args = ["machine", "create", "--name", name]
        if let cpus { args.append(contentsOf: ["--cpus", "\(cpus)"]) }
        if let memoryGB { args.append(contentsOf: ["--memory", "\(Int(memoryGB))G"]) }
        if let platform, !platform.isEmpty, platform != "auto" {
            args.append(contentsOf: ["--platform", platform])
        }
        args.append(image)
        _ = try await runCommand(args)
    }

    /// Stop a running machine.
    func stopMachine(name: String) async throws {
        logger.info("Stopping machine: \(name)")
        _ = try await runCommand(["machine", "stop", name])
    }

    /// Boot a machine by running a trivial command (machine has no explicit "start").
    func startMachine(name: String) async throws {
        logger.info("Starting machine: \(name)")
        _ = try await runCommand(["machine", "run", "-n", name, "--", "true"])
    }

    /// Delete a machine.
    func deleteMachine(name: String) async throws {
        logger.info("Deleting machine: \(name)")
        _ = try await runCommand(["machine", "delete", name])
    }

    // MARK: - Helper Methods

    private func parseFileLine(_ line: String, parentPath: String) -> FileInfo? {
        guard !line.isEmpty, !line.hasPrefix("total ") else { return nil }

        let pattern = #"^(\S+)\s+\d+\s+(\S+)\s+(\S+)\s+(\d+)\s+(.{12})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 7 else {
            return nil
        }

        func value(_ index: Int) -> String {
            guard let range = Range(match.range(at: index), in: line) else { return "" }
            return String(line[range])
        }

        let permissions = value(1)
        let owner = value(2)
        let group = value(3)
        let size = Int64(value(4)) ?? 0
        let modified = value(5).trimmingCharacters(in: .whitespaces)
        let rawName = value(6)

        guard rawName != "." else { return nil }

        let parts = rawName.components(separatedBy: " -> ")
        let name = parts.first ?? rawName
        guard name != ".." else { return nil }

        let cleanParent = parentPath == "/" ? "" : parentPath
        let fullPath = "\(cleanParent)/\(name)"

        return FileInfo(
            id: fullPath,
            name: name,
            path: fullPath,
            permissions: permissions,
            owner: owner,
            group: group,
            size: size,
            modified: modified,
            isDirectory: permissions.hasPrefix("d"),
            isSymlink: permissions.hasPrefix("l"),
            symlinkTarget: parts.count > 1 ? parts.dropFirst().joined(separator: " -> ") : nil
        )
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Execute a container command and return output
    private func runCommand(_ arguments: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()

            // Use /bin/zsh to execute container command with full path
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")

            let commandString = "/usr/local/bin/container " + arguments.map(shellQuote).joined(separator: " ")
            process.arguments = ["-c", commandString]

            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus != 0 {
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    logger.error("Command failed: \(errorMessage)")
                    continuation.resume(throwing: CLIError.commandFailed(process.terminationStatus, errorMessage))
                } else {
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                }
            } catch {
                logger.error("Failed to execute command: \(error)")
                continuation.resume(throwing: CLIError.executionFailed(error.localizedDescription))
            }
        }
    }
}

// MARK: - Errors

enum CLIError: Error, LocalizedError {
    case commandFailed(Int32, String)
    case executionFailed(String)
    case invalidOutput(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let code, let message):
            return "Command failed with code \(code): \(message)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .invalidOutput(let message):
            return "Invalid output: \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}
