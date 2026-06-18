import Foundation

// MARK: - Container Specification

/// Container configuration specification
struct ContainerSpec: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var image: String              // Image reference (e.g., "alpine:latest")
    var cpus: Int                  // Number of CPUs (default: 2)
    var memoryBytes: UInt64        // Memory in bytes (default: 2GB)
    var rootfsSizeBytes: UInt64    // Rootfs size in bytes (default: 10GB)
    var command: [String]          // Startup command
    var workingDirectory: String   // Working directory (default: "/")
    var environment: [String: String] = [:]
    var publishedPorts: [String] = []   // e.g. "8080:80" or "127.0.0.1:5432:5432"
    var network: String? = nil
    var platform: String? = nil         // e.g. "linux/arm64"; nil = CLI default
    var volumeBinds: [String] = []      // e.g. "/host/path:/container/path"
    var mounts: [MountSpec] = []
    var rosettaEnabled: Bool = false
    var autostart: Bool = false

    init(
        id: String = UUID().uuidString,
        name: String,
        image: String,
        cpus: Int = 2,
        memoryBytes: UInt64 = 2 * 1024 * 1024 * 1024, // 2GB
        rootfsSizeBytes: UInt64 = 10 * 1024 * 1024 * 1024, // 10GB
        command: [String] = ["/bin/sh"],
        workingDirectory: String = "/"
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.cpus = cpus
        self.memoryBytes = memoryBytes
        self.rootfsSizeBytes = rootfsSizeBytes
        self.command = command
        self.workingDirectory = workingDirectory
    }
}

// MARK: - Mount Specification

/// Mount specification for container volumes
struct MountSpec: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var hostBookmarkID: String     // Security-scoped bookmark ID
    var guestPath: String          // Path inside container
    var readOnly: Bool = false
}

// MARK: - Container Status

/// Container runtime status
enum ContainerStatus: String, Codable, CaseIterable {
    case creating  // Being created
    case created   // Created but not started
    case starting  // Starting up
    case running   // Running
    case stopping  // Stopping
    case stopped   // Stopped
    case failed    // Failed to start or crashed

    var displayName: String {
        switch self {
        case .creating: return NSLocalizedString("status.creating", value: "Creating", comment: "Container status")
        case .created: return NSLocalizedString("status.created", value: "Created", comment: "Container status")
        case .starting: return NSLocalizedString("status.starting", value: "Starting", comment: "Container status")
        case .running: return NSLocalizedString("status.running", value: "Running", comment: "Container status")
        case .stopping: return NSLocalizedString("status.stopping", value: "Stopping", comment: "Container status")
        case .stopped: return NSLocalizedString("status.stopped", value: "Stopped", comment: "Container status")
        case .failed: return NSLocalizedString("status.failed", value: "Failed", comment: "Container status")
        }
    }

    var isActive: Bool {
        switch self {
        case .starting, .running:
            return true
        default:
            return false
        }
    }

    var canStart: Bool {
        switch self {
        case .created, .stopped, .failed:
            return true
        default:
            return false
        }
    }

    var canStop: Bool {
        switch self {
        case .starting, .running:
            return true
        default:
            return false
        }
    }
}

// MARK: - Container Summary

/// Container summary for UI display
struct ContainerSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let image: String
    var status: ContainerStatus
    let cpus: Int
    let memoryBytes: UInt64
    let createdAt: Date
    var startedAt: Date?
    var stoppedAt: Date?
    var exitCode: Int?
    var lastError: String?

    var memoryDisplayString: String {
        let gb = Double(memoryBytes) / (1024 * 1024 * 1024)
        return String(format: "%.1f GB", gb)
    }

    var uptimeString: String? {
        guard let startedAt = startedAt, status == .running else {
            return nil
        }
        let interval = Date().timeIntervalSince(startedAt)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Log Line

/// Log line from container output
struct LogLine: Identifiable, Hashable {
    let id: UUID = UUID()
    let timestamp: Date
    let stream: LogStream
    let content: String

    enum LogStream: String, Codable {
        case stdout
        case stderr
    }
}

// MARK: - Container Error

/// Container-specific errors
enum ContainerError: Error, LocalizedError {
    case runtimeNotBootstrapped
    case containerNotFound(String)
    case containerAlreadyExists(String)
    case invalidConfiguration(String)
    case startFailed(String)
    case stopFailed(String)
    case deleteFailed(String)
    case imageNotAvailable(String)

    var errorDescription: String? {
        switch self {
        case .runtimeNotBootstrapped:
            return "Container runtime is not initialized"
        case .containerNotFound(let id):
            return "Container not found: \(id)"
        case .containerAlreadyExists(let name):
            return "Container with name '\(name)' already exists"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .startFailed(let reason):
            return "Failed to start container: \(reason)"
        case .stopFailed(let reason):
            return "Failed to stop container: \(reason)"
        case .deleteFailed(let reason):
            return "Failed to delete container: \(reason)"
        case .imageNotAvailable(let image):
            return "Image not available: \(image)"
        }
    }
}
