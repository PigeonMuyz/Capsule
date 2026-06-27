import Foundation
import SwiftUI
import Combine

struct ComposeRemovalOptions: Hashable {
    var deleteCreatedNetworks = true
    var deleteCreatedVolumes = true
    var deleteImages = false
}

/// Manages all Docker Compose projects
@MainActor
class ComposeManager: ObservableObject {
    @Published var projects: [ComposeProjectInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let runtime: RuntimeCore
    private var activeProjects: [String: ComposeProjectWrapper] = [:] // project ID -> wrapper
    private let storageKey = "composeProjects.v1"

    init(runtime: RuntimeCore) {
        self.runtime = runtime
        restoreProjects()
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
        var createdProjectID: String?

        do {
            // Create project wrapper
            let wrapper = ComposeProjectWrapper(
                name: name,
                services: services,
                volumes: volumes,
                networks: networks,
                runtime: runtime
            )
            createdProjectID = wrapper.id

            activeProjects[wrapper.id] = wrapper

            let info = ComposeProjectInfo(
                id: wrapper.id,
                name: name,
                services: services.map { ComposeProjectInfo.ServiceInfo(service: $0, projectName: name) },
                status: .creating,
                createdVolumes: [],
                createdNetworks: []
            )
            projects.append(info)
            persistProjects()

            try await wrapper.start()
            syncProjectResources(id: wrapper.id)

            if let status = try? await wrapper.status() {
                updateProjectStatus(id: wrapper.id, status: status.projectStatus)
            } else {
                updateProjectStatus(id: wrapper.id, status: .running)
            }

            isLoading = false
            return wrapper.id
        } catch {
            errorMessage = error.localizedDescription
            if let projectID = createdProjectID {
                updateProjectStatus(id: projectID, status: .error)
            }
            isLoading = false
            throw error
        }
    }

    func createProjectInBackground(
        name: String,
        services: [ComposeProject.ComposeService],
        volumes: [String],
        networks: [String]
    ) {
        Task {
            do {
                _ = try await createProject(
                    name: name,
                    services: services,
                    volumes: volumes,
                    networks: networks
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateProjectStatus(id: String, status: ComposeProjectInfo.ProjectStatus) {
        if let index = projects.firstIndex(where: { $0.id == id }) {
            guard projects[index].status != status else { return }
            projects[index].status = status
            persistProjects()
        }
    }

    private func syncProjectResources(id: String) {
        guard let wrapper = activeProjects[id],
              let index = projects.firstIndex(where: { $0.id == id }) else {
            return
        }

        let createdVolumes = wrapper.createdVolumeNames
        let createdNetworks = wrapper.createdNetworkNames
        guard projects[index].createdVolumes != createdVolumes || projects[index].createdNetworks != createdNetworks else {
            return
        }

        projects[index].createdVolumes = createdVolumes
        projects[index].createdNetworks = createdNetworks
        persistProjects()
    }

    /// Stop a project
    func stopProject(id: String) async throws {
        guard let wrapper = activeProjects[id] else {
            throw ComposeManagerError.projectNotFound(id)
        }

        try await wrapper.stop()

        if let index = projects.firstIndex(where: { $0.id == id }) {
            projects[index].status = .stopped
            persistProjects()
        }
    }

    /// Force stop all containers in a project.
    func forceStopProject(id: String) async throws {
        guard let wrapper = activeProjects[id] else {
            throw ComposeManagerError.projectNotFound(id)
        }

        try await wrapper.forceStop()

        if let index = projects.firstIndex(where: { $0.id == id }) {
            projects[index].status = .stopped
            persistProjects()
        }
    }

    /// Start a stopped project
    func startProject(id: String) async throws {
        guard let wrapper = activeProjects[id] else {
            throw ComposeManagerError.projectNotFound(id)
        }

        updateProjectStatus(id: id, status: .creating)
        do {
            try await wrapper.start()
            syncProjectResources(id: id)
            if let status = try? await wrapper.status() {
                updateProjectStatus(id: id, status: status.projectStatus)
            } else {
                updateProjectStatus(id: id, status: .running)
            }
        } catch {
            updateProjectStatus(id: id, status: .error)
            throw error
        }
    }

    /// Remove a project (stop and delete all resources)
    func removeProject(id: String, removeVolumes: Bool = false) async throws {
        let options = ComposeRemovalOptions(
            deleteCreatedNetworks: true,
            deleteCreatedVolumes: removeVolumes,
            deleteImages: false
        )
        try await removeProject(id: id, options: options)
    }

    /// Remove a project with explicit resource cleanup choices.
    func removeProject(id: String, options: ComposeRemovalOptions) async throws {
        guard let wrapper = activeProjects[id] else {
            throw ComposeManagerError.projectNotFound(id)
        }

        try await wrapper.down(options: options)

        activeProjects.removeValue(forKey: id)
        projects.removeAll { $0.id == id }
        persistProjects()
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
                    let projectStatus = status.projectStatus
                    let createdVolumes = wrapper.createdVolumeNames
                    let createdNetworks = wrapper.createdNetworkNames
                    if projects[index].status != projectStatus
                        || projects[index].createdVolumes != createdVolumes
                        || projects[index].createdNetworks != createdNetworks {
                        projects[index].status = projectStatus
                        projects[index].createdVolumes = createdVolumes
                        projects[index].createdNetworks = createdNetworks
                        persistProjects()
                    }
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
        let services: [ServiceInfo]
        var status: ProjectStatus
        var createdVolumes: [String]
        var createdNetworks: [String]

        var serviceCount: Int { services.count }
        var imageReferences: [String] {
            Array(Set(services.map(\.image).filter { !$0.isEmpty })).sorted()
        }

        struct ServiceInfo: Hashable, Identifiable {
            let name: String
            let containerName: String
            let image: String

            var id: String { name }

            init(service: ComposeProject.ComposeService, projectName: String) {
                name = service.name
                containerName = service.containerName.isEmpty ? "\(projectName)-\(service.name)" : service.containerName
                image = service.image
            }

            init(name: String, containerName: String, image: String) {
                self.name = name
                self.containerName = containerName
                self.image = image
            }
        }

        enum ProjectStatus: String, Codable {
            case creating
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

        var projectStatus: ComposeProjectInfo.ProjectStatus {
            if isRunning {
                return .running
            }
            if isStopped {
                return .stopped
            }
            return .partial
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
                let format = NSLocalizedString("Project '%@' not found", comment: "Compose manager error with project id")
                return String(format: format, id)
            }
        }
    }

    private struct StoredComposeProject: Codable {
        let id: String
        let name: String
        let services: [StoredComposeService]
        let volumes: [String]
        let networks: [String]
        let createdVolumes: [String]?
        let createdNetworks: [String]?
        let containerIDs: [String: String]
        let status: ComposeProjectInfo.ProjectStatus
    }

    private struct StoredComposeService: Codable {
        let name: String
        let containerName: String
        let image: String
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

        init(service: ComposeProject.ComposeService) {
            name = service.name
            containerName = service.containerName
            image = service.image
            portBindings = service.portBindings
            volumes = service.volumes
            environment = service.environment
            dependsOn = service.dependsOn
            networks = service.networks
            restartPolicy = service.restartPolicy
            healthcheck = service.healthcheck
            cpus = service.cpus
            memoryGB = service.memoryGB
            command = service.command
        }

        func composeService() -> ComposeProject.ComposeService {
            ComposeProject.ComposeService(
                name: name,
                containerName: containerName,
                image: image,
                ports: [],
                portBindings: portBindings,
                volumes: volumes,
                environment: environment,
                dependsOn: dependsOn,
                networks: networks,
                restartPolicy: restartPolicy,
                healthcheck: healthcheck,
                cpus: cpus,
                memoryGB: memoryGB,
                command: command
            )
        }
    }

    private func persistProjects() {
        let stored = projects.compactMap { project -> StoredComposeProject? in
            guard let wrapper = activeProjects[project.id] else { return nil }
            return StoredComposeProject(
                id: project.id,
                name: project.name,
                services: wrapper.services.map(StoredComposeService.init),
                volumes: wrapper.volumes,
                networks: wrapper.networks,
                createdVolumes: wrapper.createdVolumeNames,
                createdNetworks: wrapper.createdNetworkNames,
                containerIDs: wrapper.containerIDs,
                status: project.status
            )
        }

        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func restoreProjects() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let storedProjects = try? JSONDecoder().decode([StoredComposeProject].self, from: data) else {
            return
        }

        for stored in storedProjects {
            let services = stored.services.map { $0.composeService() }
            let wrapper = ComposeProjectWrapper(
                id: stored.id,
                name: stored.name,
                services: services,
                volumes: stored.volumes,
                networks: stored.networks,
                runtime: runtime,
                containerIDs: stored.containerIDs,
                createdVolumes: stored.createdVolumes ?? stored.volumes,
                createdNetworks: stored.createdNetworks ?? stored.networks
            )
            activeProjects[stored.id] = wrapper
            projects.append(
                ComposeProjectInfo(
                    id: stored.id,
                    name: stored.name,
                    services: services.map { ComposeProjectInfo.ServiceInfo(service: $0, projectName: stored.name) },
                    status: stored.status == .creating ? .partial : stored.status,
                    createdVolumes: wrapper.createdVolumeNames,
                    createdNetworks: wrapper.createdNetworkNames
                )
            )
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
    private var createdVolumes: Set<String>
    private var createdNetworks: Set<String>

    var createdVolumeNames: [String] { createdVolumes.sorted() }
    var createdNetworkNames: [String] { createdNetworks.sorted() }
    var imageReferences: [String] {
        Array(Set(services.map(\.image).filter { !$0.isEmpty })).sorted()
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        services: [ComposeProject.ComposeService],
        volumes: [String],
        networks: [String],
        runtime: RuntimeCore,
        containerIDs: [String: String] = [:],
        createdVolumes: [String] = [],
        createdNetworks: [String] = []
    ) {
        self.id = id
        self.name = name
        self.services = services
        self.volumes = volumes
        self.networks = networks
        self.runtime = runtime
        self.containerIDs = containerIDs
        self.createdVolumes = Set(createdVolumes)
        self.createdNetworks = Set(createdNetworks)
    }

    func start() async throws {
        // Create networks
        let existingNetworks = Set(((try? await runtime.listNetworks()) ?? []).map(\.name))
        var ensuredNetworks = Set<String>()
        for networkName in networks {
            let networkName = networkName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !networkName.isEmpty, ensuredNetworks.insert(networkName).inserted else { continue }
            guard !existingNetworks.contains(networkName) else { continue }
            try await runtime.createNetwork(name: networkName)
            createdNetworks.insert(networkName)
        }

        // Create volumes
        let existingVolumes = Set(((try? await runtime.listVolumes()) ?? []).map(\.name))
        var ensuredVolumes = Set<String>()
        for volumeName in volumes {
            let volumeName = volumeName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !volumeName.isEmpty, ensuredVolumes.insert(volumeName).inserted else { continue }
            guard !existingVolumes.contains(volumeName) else { continue }
            do {
                try await runtime.createVolume(name: volumeName)
                createdVolumes.insert(volumeName)
            } catch {
                // Volume create can fail if another process created it between list and create.
                continue
            }
        }

        if !containerIDs.isEmpty {
            for (_, containerID) in containerIDs {
                try await runtime.startContainer(id: containerID)
            }
            return
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
            spec.labels.append("io.github.pigeonmuyz.capsule.compose.project=\(name)")
            spec.labels.append("io.github.pigeonmuyz.capsule.compose.service=\(service.name)")
            spec.labels.append("com.docker.compose.project=\(name)")
            spec.labels.append("com.docker.compose.service=\(service.name)")

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

    func forceStop() async throws {
        for (_, containerID) in containerIDs.reversed() {
            try? await runtime.forceStopContainer(id: containerID)
        }
    }

    func down(options: ComposeRemovalOptions) async throws {
        try await stop()

        for (_, containerID) in containerIDs {
            try? await runtime.deleteContainer(id: containerID)
        }
        containerIDs.removeAll()

        if options.deleteCreatedVolumes {
            for volumeName in createdVolumeNames {
                try? await runtime.deleteVolume(name: volumeName)
            }
        }

        if options.deleteCreatedNetworks {
            for networkName in createdNetworkNames {
                try? await runtime.deleteNetwork(name: networkName)
            }
        }

        if options.deleteImages {
            for image in imageReferences {
                try? await runtime.deleteImage(id: image)
            }
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
