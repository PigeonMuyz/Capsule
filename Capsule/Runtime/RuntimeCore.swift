import Foundation
import OSLog

private let logger = Logger(subsystem: "io.github.pigeonmuyz.capsule", category: "runtime")

/// Core runtime for managing containers
/// This actor encapsulates all container lifecycle operations using Apple Containerization framework
actor RuntimeCore {
    // MARK: - Properties

    private var containers: [String: ManagedContainer] = [:]
    private var isBootstrapped = false

    // MARK: - Managed Container

    private struct ManagedContainer {
        let spec: ContainerSpec
        var status: ContainerStatus
        var startedAt: Date?
        var stoppedAt: Date?
        var exitCode: Int?
        var lastError: String?

        // TODO: Will hold reference to Containerization.LinuxContainer
        // var container: LinuxContainer?
    }

    // MARK: - Initialization

    init() {
        logger.info("RuntimeCore initialized")
    }

    // MARK: - Bootstrap

    /// Bootstrap the container runtime with kernel and configuration
    /// - Parameters:
    ///   - kernelURL: URL to the Linux kernel file
    ///   - rosetta: Enable Rosetta for linux/amd64 support
    func bootstrap(kernelURL: URL, rosetta: Bool = false) async throws {
        guard !isBootstrapped else {
            logger.warning("Runtime already bootstrapped")
            return
        }

        logger.info("Bootstrapping runtime with kernel at: \(kernelURL.path)")

        // TODO: Initialize ContainerManager from Containerization framework
        // let kernel = Kernel(path: kernelURL, platform: .linuxArm)
        // let network: Network? = try? VmnetNetwork()
        // self.manager = try await ContainerManager(
        //     kernel: kernel,
        //     initfsReference: "vminit:latest",
        //     network: network,
        //     rosetta: rosetta
        // )

        isBootstrapped = true
        logger.info("Runtime bootstrapped successfully")
    }

    // MARK: - Container Lifecycle

    /// Create a new container
    /// - Parameter spec: Container specification
    /// - Returns: Container summary
    func createContainer(_ spec: ContainerSpec) async throws -> ContainerSummary {
        guard isBootstrapped else {
            throw ContainerError.runtimeNotBootstrapped
        }

        // Check for duplicate names
        if containers.values.contains(where: { $0.spec.name == spec.name }) {
            throw ContainerError.containerAlreadyExists(spec.name)
        }

        logger.info("Creating container: \(spec.name) (id: \(spec.id))")

        // TODO: Create container using Containerization framework
        // let container = try await manager.create(
        //     spec.id,
        //     reference: spec.image,
        //     rootfsSizeInBytes: spec.rootfsSizeBytes,
        //     readOnly: false,
        //     networking: true
        // ) { config in
        //     config.cpus = spec.cpus
        //     config.memoryInBytes = spec.memoryBytes
        //     config.process.arguments = spec.command
        //     config.process.workingDirectory = spec.workingDirectory
        //
        //     for (key, value) in spec.environment {
        //         config.process.environment[key] = value
        //     }
        // }

        let managed = ManagedContainer(
            spec: spec,
            status: .created,
            startedAt: nil,
            stoppedAt: nil,
            exitCode: nil,
            lastError: nil
        )

        containers[spec.id] = managed

        logger.info("Container created: \(spec.name)")
        return makeSummary(from: managed)
    }

    /// Start a container
    /// - Parameter id: Container ID
    func startContainer(id: String) async throws {
        guard isBootstrapped else {
            throw ContainerError.runtimeNotBootstrapped
        }

        guard var managed = containers[id] else {
            throw ContainerError.containerNotFound(id)
        }

        logger.info("Starting container: \(managed.spec.name)")

        managed.status = .starting
        managed.startedAt = Date()
        managed.exitCode = nil
        managed.lastError = nil
        containers[id] = managed

        do {
            // TODO: Start container using Containerization framework
            // try await container.create()
            // try await container.start()

            // Simulate startup
            try await Task.sleep(for: .seconds(1))

            managed.status = .running
            containers[id] = managed

            logger.info("Container started: \(managed.spec.name)")

            // TODO: Monitor container exit
            // Task {
            //     try await container.wait()
            //     await handleContainerExit(id: id, exitCode: 0)
            // }

        } catch {
            managed.status = .failed
            managed.lastError = error.localizedDescription
            containers[id] = managed
            logger.error("Failed to start container \(managed.spec.name): \(error)")
            throw ContainerError.startFailed(error.localizedDescription)
        }
    }

    /// Stop a container
    /// - Parameter id: Container ID
    func stopContainer(id: String) async throws {
        guard isBootstrapped else {
            throw ContainerError.runtimeNotBootstrapped
        }

        guard var managed = containers[id] else {
            throw ContainerError.containerNotFound(id)
        }

        logger.info("Stopping container: \(managed.spec.name)")

        managed.status = .stopping
        containers[id] = managed

        do {
            // TODO: Stop container using Containerization framework
            // try await container.stop()

            // Simulate shutdown
            try await Task.sleep(for: .milliseconds(500))

            managed.status = .stopped
            managed.stoppedAt = Date()
            containers[id] = managed

            logger.info("Container stopped: \(managed.spec.name)")

        } catch {
            managed.status = .failed
            managed.lastError = error.localizedDescription
            containers[id] = managed
            logger.error("Failed to stop container \(managed.spec.name): \(error)")
            throw ContainerError.stopFailed(error.localizedDescription)
        }
    }

    /// Delete a container
    /// - Parameter id: Container ID
    func deleteContainer(id: String) async throws {
        guard var managed = containers[id] else {
            throw ContainerError.containerNotFound(id)
        }

        logger.info("Deleting container: \(managed.spec.name)")

        // Stop if running
        if managed.status.isActive {
            try await stopContainer(id: id)
        }

        do {
            // TODO: Delete container using Containerization framework
            // try await manager.delete(id)
            // Clean up rootfs

            containers.removeValue(forKey: id)
            logger.info("Container deleted: \(managed.spec.name)")

        } catch {
            logger.error("Failed to delete container \(managed.spec.name): \(error)")
            throw ContainerError.deleteFailed(error.localizedDescription)
        }
    }

    /// List all containers
    /// - Returns: Array of container summaries
    func listContainers() async -> [ContainerSummary] {
        return containers.values.map { makeSummary(from: $0) }
    }

    /// Get container by ID
    /// - Parameter id: Container ID
    /// - Returns: Container summary
    func getContainer(id: String) async throws -> ContainerSummary {
        guard let managed = containers[id] else {
            throw ContainerError.containerNotFound(id)
        }
        return makeSummary(from: managed)
    }

    // MARK: - Private Helpers

    private func makeSummary(from managed: ManagedContainer) -> ContainerSummary {
        ContainerSummary(
            id: managed.spec.id,
            name: managed.spec.name,
            image: managed.spec.image,
            status: managed.status,
            cpus: managed.spec.cpus,
            memoryBytes: managed.spec.memoryBytes,
            createdAt: Date(), // TODO: Track actual creation time
            startedAt: managed.startedAt,
            stoppedAt: managed.stoppedAt,
            exitCode: managed.exitCode,
            lastError: managed.lastError
        )
    }

    private func handleContainerExit(id: String, exitCode: Int) {
        guard var managed = containers[id] else { return }

        logger.info("Container exited: \(managed.spec.name) (exit code: \(exitCode))")

        managed.status = .stopped
        managed.stoppedAt = Date()
        managed.exitCode = exitCode
        containers[id] = managed
    }
}
