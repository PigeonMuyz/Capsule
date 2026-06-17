import Foundation
import SwiftUI
import Combine
import OSLog

private let logger = Logger(subsystem: "io.github.pigeonmuyz.capsule", category: "viewmodel")

/// ViewModel for container management UI
@MainActor
class ContainerViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var containers: [ContainerSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let runtime = RuntimeCore()
    private let logService = LogService()
    private var updateTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        logger.info("ContainerViewModel initialized")
        startPeriodicRefresh()
    }

    deinit {
        updateTask?.cancel()
    }

    // MARK: - Container Operations

    /// Create a new container
    func createContainer(spec: ContainerSpec) async {
        isLoading = true
        errorMessage = nil

        do {
            logger.info("Creating container: \(spec.name)")
            let summary = try await runtime.createContainer(spec)

            // Add initial log entry
            await logService.appendLog(
                containerID: summary.id,
                stream: .stdout,
                content: "Container '\(summary.name)' created"
            )

            await refreshContainers()
            logger.info("Container created successfully: \(spec.name)")
        } catch {
            logger.error("Failed to create container: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Start a container
    func startContainer(id: String) async {
        do {
            logger.info("Starting container: \(id)")

            await logService.appendLog(
                containerID: id,
                stream: .stdout,
                content: "Starting container..."
            )

            try await runtime.startContainer(id: id)

            await logService.appendLog(
                containerID: id,
                stream: .stdout,
                content: "Container started successfully"
            )

            // Simulate some container output for MVP
            await simulateContainerOutput(id: id)

            await refreshContainers()
            logger.info("Container started: \(id)")
        } catch {
            logger.error("Failed to start container: \(error.localizedDescription)")
            errorMessage = error.localizedDescription

            await logService.appendLog(
                containerID: id,
                stream: .stderr,
                content: "Error: \(error.localizedDescription)"
            )
        }
    }

    /// Stop a container
    func stopContainer(id: String) async {
        do {
            logger.info("Stopping container: \(id)")

            await logService.appendLog(
                containerID: id,
                stream: .stdout,
                content: "Stopping container..."
            )

            try await runtime.stopContainer(id: id)

            await logService.appendLog(
                containerID: id,
                stream: .stdout,
                content: "Container stopped"
            )

            await refreshContainers()
            logger.info("Container stopped: \(id)")
        } catch {
            logger.error("Failed to stop container: \(error.localizedDescription)")
            errorMessage = error.localizedDescription

            await logService.appendLog(
                containerID: id,
                stream: .stderr,
                content: "Error: \(error.localizedDescription)"
            )
        }
    }

    /// Delete a container
    func deleteContainer(id: String) async {
        do {
            logger.info("Deleting container: \(id)")
            try await runtime.deleteContainer(id: id)
            await logService.removeContainer(containerID: id)
            await refreshContainers()
            logger.info("Container deleted: \(id)")
        } catch {
            logger.error("Failed to delete container: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Log Operations

    /// Get logs for a container
    func getLogs(containerID: String) async -> [LogLine] {
        return await logService.getAllLogs(containerID: containerID)
    }

    /// Stream logs for a container
    func streamLogs(containerID: String) async -> AsyncStream<LogLine> {
        return await logService.streamLogs(containerID: containerID)
    }

    /// Clear logs for a container
    func clearLogs(containerID: String) async {
        await logService.clearLogs(containerID: containerID)
    }

    // MARK: - Private Methods

    private func refreshContainers() async {
        containers = await runtime.listContainers()
    }

    private func startPeriodicRefresh() {
        updateTask = Task {
            while !Task.isCancelled {
                await refreshContainers()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Simulate container output for MVP (will be replaced with real container stdout/stderr)
    private func simulateContainerOutput(id: String) async {
        // Get container info
        guard let container = containers.first(where: { $0.id == id }) else {
            return
        }

        // Simulate some output based on the image
        Task {
            try? await Task.sleep(for: .milliseconds(500))

            if container.image.contains("alpine") {
                await logService.appendLog(
                    containerID: id,
                    stream: .stdout,
                    content: "Alpine Linux running"
                )
                await logService.appendLog(
                    containerID: id,
                    stream: .stdout,
                    content: "Hostname: \(container.name)"
                )
            } else {
                await logService.appendLog(
                    containerID: id,
                    stream: .stdout,
                    content: "Container is running"
                )
            }

            // Simulate command execution
            let spec = try? await runtime.getContainer(id: id)
            if let command = spec?.lastError { // This is a hack for MVP, will be fixed
                await logService.appendLog(
                    containerID: id,
                    stream: .stdout,
                    content: "$ \(container.image)"
                )
            }
        }
    }
}
