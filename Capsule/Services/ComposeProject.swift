import Foundation
import OSLog

private let logger = Logger(subsystem: "io.github.pigeonmuyz.capsule", category: "compose")

/// Manages a Docker Compose project lifecycle
actor ComposeProject {
    let id: String
    let name: String
    let services: [ComposeService]
    private(set) var containerIDs: [String: String] = [:] // service name -> container ID
    var volumeNames: [String] = []
    var networkNames: [String] = []

    private let runtime: RuntimeCore

    struct ComposeService {
        let name: String
        let containerName: String
        let image: String
        let ports: [(host: Int, container: Int)]
        let portBindings: [String]
        let volumes: [String]
        let environment: [String: String]
        let dependsOn: [String]
        let networks: [String]
        let restartPolicy: String?
        let healthcheck: Bool
        let cpus: Int
        let memoryGB: Int
        let command: [String]
    }

    init(name: String, services: [ComposeService], runtime: RuntimeCore) {
        self.id = UUID().uuidString
        self.name = name
        self.services = services
        self.runtime = runtime
    }

    // MARK: - Lifecycle Management

    /// Start all services in dependency order
    func start() async throws {
        logger.info("Starting compose project: \(self.name)")

        // Create networks first
        for networkName in networkNames {
            do {
                try await runtime.createNetwork(name: networkName, driver: "bridge")
                logger.info("Created network: \(networkName)")
            } catch {
                logger.warning("Network \(networkName) may already exist: \(error)")
            }
        }

        // Create volumes
        for volumeName in volumeNames {
            do {
                try await runtime.createVolume(name: volumeName)
                logger.info("Created volume: \(volumeName)")
            } catch {
                logger.warning("Volume \(volumeName) may already exist: \(error)")
            }
        }

        // Sort services by dependency order
        let sortedServices = try topologicalSort(services: services)

        // Create and start containers in order
        for service in sortedServices {
            do {
                var spec = ContainerSpec(
                    name: service.containerName.isEmpty ? "\(name)-\(service.name)" : service.containerName,
                    image: service.image,
                    cpus: service.cpus,
                    memoryBytes: UInt64(service.memoryGB) * 1024 * 1024 * 1024,
                    command: service.command
                )
                spec.environment = service.environment
                spec.publishedPorts = service.portBindings.isEmpty
                    ? service.ports.map { "\($0.host):\($0.container)" }
                    : service.portBindings
                spec.volumeBinds = service.volumes
                spec.network = service.networks.first
                spec.restartPolicy = RestartPolicy(rawValue: service.restartPolicy ?? "") ?? .no

                let summary = try await runtime.createContainer(spec)
                containerIDs[service.name] = summary.id

                try await runtime.startContainer(id: summary.id)
                logger.info("Started service: \(service.name)")

                // Wait a bit for dependencies to be ready
                try await Task.sleep(for: .seconds(1))
            } catch {
                logger.error("Failed to start service \(service.name): \(error)")
                throw ComposeError.serviceStartFailed(service.name, error)
            }
        }

        logger.info("Compose project \(self.name) started successfully")
    }

    /// Stop all services
    func stop() async throws {
        logger.info("Stopping compose project: \(self.name)")

        // Stop containers in reverse order
        for (serviceName, containerID) in containerIDs.reversed() {
            do {
                try await runtime.stopContainer(id: containerID)
                logger.info("Stopped service: \(serviceName)")
            } catch {
                logger.warning("Failed to stop service \(serviceName): \(error)")
            }
        }

        logger.info("Compose project \(self.name) stopped")
    }

    /// Remove all resources (containers, volumes, networks)
    func down(removeVolumes: Bool = false) async throws {
        logger.info("Removing compose project: \(self.name)")

        // Stop first
        try await stop()

        // Delete containers
        for (serviceName, containerID) in containerIDs {
            do {
                try await runtime.deleteContainer(id: containerID)
                logger.info("Removed container: \(serviceName)")
            } catch {
                logger.warning("Failed to remove container \(serviceName): \(error)")
            }
        }

        containerIDs.removeAll()

        // Delete volumes if requested
        if removeVolumes {
            for volumeName in volumeNames {
                do {
                    try await runtime.deleteVolume(name: volumeName)
                    logger.info("Removed volume: \(volumeName)")
                } catch {
                    logger.warning("Failed to remove volume \(volumeName): \(error)")
                }
            }
        }

        // Delete networks
        for networkName in networkNames {
            do {
                try await runtime.deleteNetwork(name: networkName)
                logger.info("Removed network: \(networkName)")
            } catch {
                logger.warning("Failed to remove network \(networkName): \(error)")
            }
        }

        logger.info("Compose project \(self.name) removed")
    }

    /// Get aggregated logs from all services
    func logs() async -> AsyncStream<(service: String, line: String)> {
        return AsyncStream { continuation in
            Task {
                for (serviceName, containerID) in containerIDs {
                    Task {
                        for try await line in await runtime.streamContainerLogs(id: containerID) {
                            continuation.yield((serviceName, line))
                        }
                    }
                }
            }
        }
    }

    /// Get project status
    func status() async throws -> ProjectStatus {
        var serviceStatuses: [String: ServiceStatus] = [:]

        for (serviceName, containerID) in containerIDs {
            do {
                let containers = try await runtime.listContainers()
                if let container = containers.first(where: { $0.id == containerID }) {
                    serviceStatuses[serviceName] = ServiceStatus(
                        name: serviceName,
                        containerID: containerID,
                        status: container.status,
                        image: container.image
                    )
                }
            } catch {
                logger.warning("Failed to get status for \(serviceName): \(error)")
            }
        }

        return ProjectStatus(
            name: name,
            services: serviceStatuses,
            volumes: volumeNames,
            networks: networkNames
        )
    }

    // MARK: - Dependency Resolution

    private func topologicalSort(services: [ComposeService]) throws -> [ComposeService] {
        var sorted: [ComposeService] = []
        var visited = Set<String>()
        var visiting = Set<String>()

        func visit(_ service: ComposeService) throws {
            if visited.contains(service.name) {
                return
            }

            if visiting.contains(service.name) {
                throw ComposeError.circularDependency(service.name)
            }

            visiting.insert(service.name)

            for depName in service.dependsOn {
                if let dep = services.first(where: { $0.name == depName }) {
                    try visit(dep)
                }
            }

            visiting.remove(service.name)
            visited.insert(service.name)
            sorted.append(service)
        }

        for service in services {
            try visit(service)
        }

        return sorted
    }

    // MARK: - Supporting Types

    struct ProjectStatus {
        let name: String
        let services: [String: ServiceStatus]
        let volumes: [String]
        let networks: [String]

        var isRunning: Bool {
            !services.isEmpty && services.values.allSatisfy { $0.status == .running }
        }

        var isStopped: Bool {
            services.values.allSatisfy { $0.status == .stopped || $0.status == .failed }
        }
    }

    struct ServiceStatus {
        let name: String
        let containerID: String
        let status: ContainerStatus
        let image: String
    }

    enum ComposeError: Error, LocalizedError {
        case serviceStartFailed(String, Error)
        case circularDependency(String)
        case serviceNotFound(String)

        var errorDescription: String? {
            switch self {
            case .serviceStartFailed(let service, let error):
                return "Failed to start service '\(service)': \(error.localizedDescription)"
            case .circularDependency(let service):
                return "Circular dependency detected involving service '\(service)'"
            case .serviceNotFound(let service):
                return "Service '\(service)' not found"
            }
        }
    }
}
