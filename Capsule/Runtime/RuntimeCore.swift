import Foundation
import OSLog

private let logger = Logger(subsystem: "io.github.pigeonmuyz.capsule", category: "runtime")

/// Core runtime for managing system containers
/// Integrates with Apple container CLI to manage all system containers
actor RuntimeCore {
    // MARK: - Properties

    private let cli = ContainerCLI()
    private var isInitialized = false

    // MARK: - Initialization

    init() {
        logger.info("RuntimeCore initialized")
    }

    // MARK: - Bootstrap

    /// Initialize the runtime (verify CLI is available)
    func bootstrap() async throws {
        guard !isInitialized else {
            logger.warning("Runtime already initialized")
            return
        }

        logger.info("Initializing runtime")

        // Verify container CLI is available
        do {
            _ = try await cli.listContainers()
            isInitialized = true
            logger.info("Runtime initialized successfully")
        } catch {
            logger.error("Failed to initialize runtime: \(error)")
            throw ContainerError.runtimeNotBootstrapped
        }
    }

    // MARK: - Container Lifecycle

    /// List all system containers
    /// - Returns: Array of container summaries
    func listContainers() async throws -> [ContainerSummary] {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        let containers = try await cli.listContainers()

        return containers.map { info in
            let status = mapState(info.status.state)
            let memoryBytes = UInt64(info.configuration.resources.memoryInBytes)

            return ContainerSummary(
                id: info.id,
                name: info.configuration.id, // Use configuration.id as name
                image: info.configuration.image.reference,
                status: status,
                cpus: info.configuration.resources.cpus,
                memoryBytes: memoryBytes,
                createdAt: parseDate(info.configuration.creationDate),
                startedAt: parseDate(info.status.startedDate),
                stoppedAt: nil,
                exitCode: nil,
                lastError: nil
            )
        }
    }

    /// Create a new container
    /// - Parameter spec: Container specification
    /// - Returns: Container summary
    func createContainer(_ spec: ContainerSpec) async throws -> ContainerSummary {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        logger.info("Creating container: \(spec.name)")

        let memoryMB = Int(spec.memoryBytes / (1024 * 1024))

        do {
            let containerID = try await cli.createContainer(
                name: spec.name,
                image: spec.image,
                cpus: spec.cpus,
                memoryMB: memoryMB,
                command: spec.command.isEmpty ? nil : spec.command
            )

            logger.info("Container created with ID: \(containerID)")

            return ContainerSummary(
                id: containerID,
                name: spec.name,
                image: spec.image,
                status: .created,
                cpus: spec.cpus,
                memoryBytes: spec.memoryBytes,
                createdAt: Date(),
                startedAt: nil,
                stoppedAt: nil,
                exitCode: nil,
                lastError: nil
            )
        } catch {
            logger.error("Failed to create container: \(error)")
            throw ContainerError.invalidConfiguration(error.localizedDescription)
        }
    }

    /// Start a container
    /// - Parameter id: Container ID
    func startContainer(id: String) async throws {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        logger.info("Starting container: \(id)")

        do {
            try await cli.startContainer(id: id)
            logger.info("Container started: \(id)")
        } catch {
            logger.error("Failed to start container: \(error)")
            throw ContainerError.startFailed(error.localizedDescription)
        }
    }

    /// Stop a container
    /// - Parameter id: Container ID
    func stopContainer(id: String) async throws {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        logger.info("Stopping container: \(id)")

        do {
            try await cli.stopContainer(id: id)
            logger.info("Container stopped: \(id)")
        } catch {
            logger.error("Failed to stop container: \(error)")
            throw ContainerError.stopFailed(error.localizedDescription)
        }
    }

    /// Delete a container
    /// - Parameter id: Container ID
    func deleteContainer(id: String) async throws {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        logger.info("Deleting container: \(id)")

        do {
            try await cli.deleteContainer(id: id)
            logger.info("Container deleted: \(id)")
        } catch {
            logger.error("Failed to delete container: \(error)")
            throw ContainerError.deleteFailed(error.localizedDescription)
        }
    }

    /// Get container by ID
    /// - Parameter id: Container ID
    /// - Returns: Container summary
    func getContainer(id: String) async throws -> ContainerSummary {
        let containers = try await listContainers()
        guard let container = containers.first(where: { $0.id == id }) else {
            throw ContainerError.containerNotFound(id)
        }
        return container
    }

    /// Get container logs
    /// - Parameters:
    ///   - id: Container ID
    ///   - tail: Number of lines to tail (optional)
    /// - Returns: Log content
    func getContainerLogs(id: String, tail: Int? = nil) async throws -> String {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        return try await cli.getContainerLogs(id: id, tail: tail)
    }

    /// Stream container logs
    /// - Parameter id: Container ID
    /// - Returns: AsyncThrowingStream of log lines
    nonisolated func streamContainerLogs(id: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                let stream = await cli.streamContainerLogs(id: id)
                for try await line in stream {
                    continuation.yield(line)
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Images

    /// List all images
    func listImages() async throws -> [ContainerCLI.ImageInfo] {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        return try await cli.listImages()
    }

    /// Pull an image
    func pullImage(reference: String) async throws {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        try await cli.pullImage(reference: reference)
    }

    /// Delete an image
    func deleteImage(id: String) async throws {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        try await cli.deleteImage(id: id)
    }

    // MARK: - Volumes

    /// List all volumes
    func listVolumes() async throws -> [ContainerCLI.VolumeInfo] {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        return try await cli.listVolumes()
    }

    /// Create a volume
    func createVolume(name: String) async throws {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        try await cli.createVolume(name: name)
    }

    /// Delete a volume
    func deleteVolume(name: String) async throws {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        try await cli.deleteVolume(name: name)
    }

    // MARK: - Networks

    /// List all networks
    func listNetworks() async throws -> [ContainerCLI.NetworkInfo] {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        return try await cli.listNetworks()
    }

    /// Create a network
    func createNetwork(name: String, driver: String = "bridge") async throws {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        try await cli.createNetwork(name: name, driver: driver)
    }

    /// Delete a network
    func deleteNetwork(name: String) async throws {
        guard isInitialized else {
            throw ContainerError.runtimeNotBootstrapped
        }

        try await cli.deleteNetwork(name: name)
    }

    // MARK: - Helper Methods

    /// Map container state string to ContainerStatus
    private func mapState(_ state: String) -> ContainerStatus {
        switch state.lowercased() {
        case "running":
            return .running
        case "stopped", "exited":
            return .stopped
        case "created":
            return .created
        case "paused":
            return .stopped // Map paused to stopped for now
        default:
            return .stopped
        }
    }

    /// Parse ISO8601 date string
    private func parseDate(_ dateString: String?) -> Date {
        guard let dateString = dateString, !dateString.isEmpty else {
            return Date()
        }

        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString) ?? Date()
    }
}
