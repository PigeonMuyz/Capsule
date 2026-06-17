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
            let status = mapState(info.state)
            let memoryBytes = parseMemory(info.memory)

            return ContainerSummary(
                id: info.id,
                name: extractName(from: info.id),
                image: info.image,
                status: status,
                cpus: info.cpus,
                memoryBytes: memoryBytes,
                createdAt: Date(), // TODO: Parse from started field
                startedAt: parseStarted(info.started),
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

    /// Parse memory string (e.g., "1024 MB") to bytes
    private func parseMemory(_ memory: String) -> UInt64 {
        let components = memory.components(separatedBy: .whitespaces)
        guard let value = components.first, let number = Double(value) else {
            return 0
        }

        let unit = components.count > 1 ? components[1].uppercased() : "MB"

        switch unit {
        case "KB":
            return UInt64(number * 1024)
        case "MB":
            return UInt64(number * 1024 * 1024)
        case "GB":
            return UInt64(number * 1024 * 1024 * 1024)
        default:
            return UInt64(number * 1024 * 1024) // Default to MB
        }
    }

    /// Parse started timestamp
    private func parseStarted(_ started: String?) -> Date? {
        guard let started = started, !started.isEmpty else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        return formatter.date(from: started)
    }

    /// Extract container name from ID (if ID contains name, otherwise return ID)
    private func extractName(from id: String) -> String {
        // Container IDs often follow pattern: name-suffix or just name
        // For now, return the full ID as name
        return id
    }
}
