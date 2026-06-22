import Foundation
import SwiftUI
import Combine

/// Manages all Docker Compose projects
@MainActor
class ComposeManager: ObservableObject {
    @Published var projects: [ComposeProjectInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let runtime: RuntimeCore
    private var activeProjects: [String: ComposeProjectWrapper] = [:] // project ID -> wrapper

    init(runtime: RuntimeCore) {
        self.runtime = runtime
    }

    // MARK: - Project Management

    /// Create and start a new compose project
    func createProject(name: String, yamlContent: String) async throws -> String {
        isLoading = true
        errorMessage = nil

        do {
            // Parse compose file
            let parsed = try DockerComposeParser.parse(yamlContent: yamlContent, appName: name)
            return try await createProject(
                name: parsed.name,
                services: parsed.services,
                volumes: parsed.volumes,
                networks: parsed.networks
            )
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            throw error
        }
    }

    func createProject(
        name: String,
        services: [ComposeProject.ComposeService],
        volumes: [String],
        networks: [String]
    ) async throws -> String {
        isLoading = true
        errorMessage = nil

        do {
            // Create project wrapper
            let wrapper = ComposeProjectWrapper(
                name: name,
                services: services,
                volumes: volumes,
                networks: networks,
                runtime: runtime
            )

            // Start project
            try await wrapper.start()

            // Track project
            activeProjects[wrapper.id] = wrapper

            let info = ComposeProjectInfo(
                id: wrapper.id,
                name: name,
                services: services.map { $0.name },
                status: .running
            )
            projects.append(info)

            isLoading = false
            return wrapper.id
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            throw error
        }
    }

    /// Stop a project
    func stopProject(id: String) async throws {
        guard let wrapper = activeProjects[id] else {
            throw ComposeManagerError.projectNotFound(id)
        }

        try await wrapper.stop()

        if let index = projects.firstIndex(where: { $0.id == id }) {
            projects[index].status = .stopped
        }
    }

    /// Start a stopped project
    func startProject(id: String) async throws {
        guard let wrapper = activeProjects[id] else {
            throw ComposeManagerError.projectNotFound(id)
        }

        try await wrapper.start()

        if let index = projects.firstIndex(where: { $0.id == id }) {
            projects[index].status = .running
        }
    }

    /// Remove a project (stop and delete all resources)
    func removeProject(id: String, removeVolumes: Bool = false) async throws {
        guard let wrapper = activeProjects[id] else {
            throw ComposeManagerError.projectNotFound(id)
        }

        try await wrapper.down(removeVolumes: removeVolumes)

        activeProjects.removeValue(forKey: id)
        projects.removeAll { $0.id == id }
    }

    /// Get project logs
    func getProjectLogs(id: String) async throws -> AsyncStream<(service: String, line: String)> {
        guard let wrapper = activeProjects[id] else {
            throw ComposeManagerError.projectNotFound(id)
        }

        return await wrapper.logs()
    }

    /// Get project status
    func getProjectStatus(id: String) async throws -> ProjectStatus {
        guard let wrapper = activeProjects[id] else {
            throw ComposeManagerError.projectNotFound(id)
        }

        return try await wrapper.status()
    }

    /// Refresh all project statuses
    func refreshProjects() async {
        for (id, wrapper) in activeProjects {
            do {
                let status = try await wrapper.status()
                if let index = projects.firstIndex(where: { $0.id == id }) {
                    projects[index].status = status.isRunning ? .running :
                                            status.isStopped ? .stopped : .partial
                }
            } catch {
                print("Failed to refresh project \(id): \(error)")
            }
        }
    }

    // MARK: - Supporting Types

    struct ComposeProjectInfo: Identifiable {
        let id: String
        let name: String
        let services: [String]
        var status: ProjectStatus

        enum ProjectStatus {
            case running
            case stopped
            case partial
            case error
        }
    }

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

    enum ComposeManagerError: Error, LocalizedError {
        case projectNotFound(String)

        var errorDescription: String? {
            switch self {
            case .projectNotFound(let id):
                return "Project '\(id)' not found"
            }
        }
    }
}

// MARK: - Compose Project Wrapper (non-actor)

class ComposeProjectWrapper {
    let id: String
    let name: String
    let services: [ComposeProject.ComposeService]
    var containerIDs: [String: String] = [:]
    let volumes: [String]
    let networks: [String]
    let runtime: RuntimeCore

    init(name: String, services: [ComposeProject.ComposeService], volumes: [String], networks: [String], runtime: RuntimeCore) {
        self.id = UUID().uuidString
        self.name = name
        self.services = services
        self.volumes = volumes
        self.networks = networks
        self.runtime = runtime
    }

    func start() async throws {
        // Create networks
        for networkName in networks {
            try? await runtime.createNetwork(name: networkName, driver: "bridge")
        }

        // Create volumes
        for volumeName in volumes {
            try? await runtime.createVolume(name: volumeName)
        }

        // Sort by dependencies
        let sorted = try topologicalSort(services: services)

        // Create and start containers
        for service in sorted {
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
            try await Task.sleep(for: .seconds(1))
        }
    }

    func stop() async throws {
        for (_, containerID) in containerIDs.reversed() {
            try? await runtime.stopContainer(id: containerID)
        }
    }

    func down(removeVolumes: Bool) async throws {
        try await stop()

        for (_, containerID) in containerIDs {
            try? await runtime.deleteContainer(id: containerID)
        }
        containerIDs.removeAll()

        if removeVolumes {
            for volumeName in volumes {
                try? await runtime.deleteVolume(name: volumeName)
            }
        }

        for networkName in networks {
            try? await runtime.deleteNetwork(name: networkName)
        }
    }

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

    func status() async throws -> ComposeManager.ProjectStatus {
        var serviceStatuses: [String: ComposeManager.ServiceStatus] = [:]

        for (serviceName, containerID) in containerIDs {
            let containers = try await runtime.listContainers()
            if let container = containers.first(where: { $0.id == containerID }) {
                serviceStatuses[serviceName] = ComposeManager.ServiceStatus(
                    name: serviceName,
                    containerID: containerID,
                    status: container.status,
                    image: container.image
                )
            }
        }

        return ComposeManager.ProjectStatus(
            name: name,
            services: serviceStatuses,
            volumes: volumes,
            networks: networks
        )
    }

    private func topologicalSort(services: [ComposeProject.ComposeService]) throws -> [ComposeProject.ComposeService] {
        var sorted: [ComposeProject.ComposeService] = []
        var visited = Set<String>()
        var visiting = Set<String>()

        func visit(_ service: ComposeProject.ComposeService) throws {
            if visited.contains(service.name) { return }
            if visiting.contains(service.name) {
                throw ComposeProject.ComposeError.circularDependency(service.name)
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
}
