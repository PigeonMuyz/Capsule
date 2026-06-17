import Foundation
import OSLog

private let logger = Logger(subsystem: "io.github.pigeonmuyz.capsule", category: "cli")

/// Wrapper for Apple `container` CLI tool
/// Provides Swift-friendly interface to system container operations
actor ContainerCLI {

    // MARK: - Container List

    struct ContainerInfo: Codable {
        let id: String
        let image: String
        let os: String
        let arch: String
        let state: String
        let ip: String?
        let cpus: Int
        let memory: String
        let started: String?

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case image = "IMAGE"
            case os = "OS"
            case arch = "ARCH"
            case state = "STATE"
            case ip = "IP"
            case cpus = "CPUS"
            case memory = "MEMORY"
            case started = "STARTED"
        }
    }

    /// List all containers in the system
    func listContainers() async throws -> [ContainerInfo] {
        logger.info("Listing containers via CLI")

        let output = try await runCommand(["container", "list", "--format", "json"])

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
        _ = try await runCommand(["container", "start", id])
        logger.info("Container started: \(id)")
    }

    /// Stop a container by ID
    func stopContainer(id: String) async throws {
        logger.info("Stopping container: \(id)")
        _ = try await runCommand(["container", "stop", id])
        logger.info("Container stopped: \(id)")
    }

    /// Delete a container by ID
    func deleteContainer(id: String) async throws {
        logger.info("Deleting container: \(id)")
        _ = try await runCommand(["container", "rm", id])
        logger.info("Container deleted: \(id)")
    }

    /// Create a new container
    func createContainer(
        name: String,
        image: String,
        cpus: Int,
        memoryMB: Int,
        command: [String]? = nil
    ) async throws -> String {
        logger.info("Creating container: \(name) with image: \(image)")

        var args = [
            "container", "create",
            "--name", name,
            "--cpus", "\(cpus)",
            "--memory", "\(memoryMB)MB",
            image
        ]

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

        var args = ["container", "logs", id]
        if let tail = tail {
            args.append(contentsOf: ["--tail", "\(tail)"])
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
                    process.arguments = ["-c", "container logs --follow \(id)"]

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
        let name: String
        let image: String
        let state: String
        let cpus: Int
        let memory: Int
        let created: String?
        let started: String?

        // Add more fields as needed based on actual container inspect output
    }

    /// Get detailed information about a container
    func inspectContainer(id: String) async throws -> ContainerDetails {
        logger.info("Inspecting container: \(id)")

        let output = try await runCommand(["container", "inspect", id])

        guard let data = output.data(using: .utf8) else {
            throw CLIError.invalidOutput("Failed to convert output to data")
        }

        do {
            let details = try JSONDecoder().decode(ContainerDetails.self, from: data)
            return details
        } catch {
            logger.error("Failed to parse container details: \(error)")
            throw CLIError.parseError(error.localizedDescription)
        }
    }

    // MARK: - Helper Methods

    /// Execute a container command and return output
    private func runCommand(_ arguments: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()

            // Use /bin/zsh to execute container command
            // This works around sandboxing issues
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "container " + arguments.map { "\"\($0)\"" }.joined(separator: " ")]

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
