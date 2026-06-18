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
    @Published var isRuntimeBootstrapped = false

    // MARK: - Private Properties

    let runtime = RuntimeCore()
    private var updateTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        logger.info("ContainerViewModel initialized")
        Task {
            // Check if auto-start is enabled
            if UserDefaults.standard.bool(forKey: "autoStartRuntime") {
                await startContainerSystemIfNeeded()
            }
            await initializeRuntime()
        }
        startPeriodicRefresh()
    }

    deinit {
        updateTask?.cancel()
    }

    // MARK: - Runtime Initialization

    func initializeRuntime() async {
        do {
            try await runtime.bootstrap()
            logger.info("Runtime bootstrapped successfully")
            isRuntimeBootstrapped = true
            await refreshContainers()
        } catch {
            logger.error("Failed to bootstrap runtime: \(error)")
            isRuntimeBootstrapped = false
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
        }
    }

    /// Start the container system service if not already running
    private func startContainerSystemIfNeeded() async {
        logger.info("Checking container system status")

        // First check if it's already running
        let checkProcess = Process()
        checkProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        checkProcess.arguments = ["-c", "/usr/local/bin/container system status 2>&1 | grep 'status' | grep -q 'running'"]

        do {
            try checkProcess.run()
            checkProcess.waitUntilExit()

            if checkProcess.terminationStatus == 0 {
                logger.info("Container system is already running")
                return
            }
        } catch {
            logger.warning("Failed to check container system status: \(error)")
        }

        // If not running, start it
        logger.info("Starting container system")
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "/usr/local/bin/container system start"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                logger.info("Container system started successfully")
                // Wait for system to initialize
                try await Task.sleep(for: .seconds(2))
            } else {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                logger.warning("Container system start returned status: \(process.terminationStatus), output: \(output)")
            }
        } catch {
            logger.error("Failed to start container system: \(error)")
        }
    }

    // MARK: - Container Operations

    /// Create a new container
    func createContainer(spec: ContainerSpec) async {
        isLoading = true
        errorMessage = nil

        do {
            logger.info("Creating container: \(spec.name)")
            let summary = try await runtime.createContainer(spec)

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

            try await runtime.startContainer(id: id)

            await refreshContainers()
            logger.info("Container started: \(id)")
        } catch {
            logger.error("Failed to start container: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Stop a container
    func stopContainer(id: String) async {
        do {
            logger.info("Stopping container: \(id)")

            try await runtime.stopContainer(id: id)

            await refreshContainers()
            logger.info("Container stopped: \(id)")
        } catch {
            logger.error("Failed to stop container: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Delete a container
    func deleteContainer(id: String) async {
        do {
            logger.info("Deleting container: \(id)")
            try await runtime.deleteContainer(id: id)
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
        // Try to get logs from system
        do {
            let logsText = try await runtime.getContainerLogs(id: containerID, tail: 100)
            let lines = logsText.components(separatedBy: .newlines)

            // Convert to LogLine objects
            var logLines: [LogLine] = []
            for line in lines where !line.isEmpty {
                let logLine = LogLine(
                    timestamp: Date(),
                    stream: .stdout,
                    content: line
                )
                logLines.append(logLine)
            }
            return logLines
        } catch {
            logger.error("Failed to get logs: \(error)")
            return []
        }
    }

    /// Stream logs for a container
    func streamLogs(containerID: String) async -> AsyncStream<LogLine> {
        return AsyncStream { continuation in
            Task {
                do {
                    for try await line in await runtime.streamContainerLogs(id: containerID) {
                        let logLine = LogLine(
                            timestamp: Date(),
                            stream: .stdout,
                            content: line
                        )
                        continuation.yield(logLine)
                    }
                    continuation.finish()
                } catch {
                    logger.error("Failed to stream logs: \(error)")
                    continuation.finish()
                }
            }
        }
    }

    /// Clear logs for a container
    func clearLogs(containerID: String) async {
        // Logs are managed by system, no need to clear
        logger.info("Clear logs requested for container: \(containerID)")
    }

    // MARK: - Private Methods

    private func refreshContainers() async {
        do {
            containers = try await runtime.listContainers()
        } catch {
            logger.error("Failed to refresh containers: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    private func startPeriodicRefresh() {
        updateTask = Task {
            while !Task.isCancelled {
                await refreshContainers()
                let interval = UserDefaults.standard.double(forKey: "autoRefreshInterval")
                let refreshInterval = interval > 0 ? interval : 2.0
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
    }
}
