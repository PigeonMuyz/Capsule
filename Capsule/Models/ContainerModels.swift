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
    var envFiles: [String] = []
    var publishedPorts: [String] = []   // e.g. "8080:80" or "127.0.0.1:5432:5432"
    var publishedSockets: [String] = []
    var network: String? = nil
    var platform: String? = nil         // e.g. "linux/arm64"; nil = CLI default
    var volumeBinds: [String] = []      // e.g. "/host/path:/container/path"
    var mounts: [MountSpec] = []
    var entrypoint: String? = nil
    var user: String? = nil
    var uid: String? = nil
    var gid: String? = nil
    var labels: [String] = []
    var ulimits: [String] = []
    var dnsServers: [String] = []
    var dnsSearchDomains: [String] = []
    var dnsOptions: [String] = []
    var noDNS: Bool = false
    var tmpfs: [String] = []
    var shmSize: String? = nil
    var capAdd: [String] = []
    var capDrop: [String] = []
    var interactive: Bool = false
    var tty: Bool = false
    var sshAgent: Bool = false
    var virtualization: Bool = false
    var rosettaEnabled: Bool = false
    var removeAfterStop: Bool = false
    var readOnlyRootfs: Bool = false
    var useInit: Bool = false
    var autostart: Bool = false
    var restartPolicy: RestartPolicy = .no

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

enum RestartPolicy: String, Codable, Hashable, CaseIterable, Identifiable {
    case no
    case always
    case unlessStopped = "unless-stopped"
    case onFailure = "on-failure"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .no: return String(localized: "No")
        case .always: return String(localized: "Always")
        case .unlessStopped: return String(localized: "Unless Stopped")
        case .onFailure: return String(localized: "On Failure")
        }
    }

    var shouldPersist: Bool { self != .no }
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

// MARK: - Container Stats

/// Container resource usage statistics (from `container stats`)
struct ContainerStats {
    let cpuPercent: Double
    let memoryUsage: UInt64
    let memoryLimit: UInt64
    let memoryPercent: Double
    let networkRx: UInt64
    let networkTx: UInt64
    let blockRead: UInt64
    let blockWrite: UInt64
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
    case invalidResponse(String)
    case startFailed(String)
    case stopFailed(String)
    case deleteFailed(String)
    case imageNotAvailable(String)

    var errorDescription: String? {
        switch self {
        case .runtimeNotBootstrapped:
            return String(localized: "Container runtime is not initialized")
        case .containerNotFound(let id):
            return String.localizedStringWithFormat(NSLocalizedString("Container not found: %@", comment: "Container not found error"), id)
        case .containerAlreadyExists(let name):
            return String.localizedStringWithFormat(NSLocalizedString("Container with name '%@' already exists", comment: "Duplicate container name error"), name)
        case .invalidConfiguration(let reason):
            return String.localizedStringWithFormat(NSLocalizedString("Invalid configuration: %@", comment: "Invalid container configuration error"), reason)
        case .invalidResponse(let reason):
            return String.localizedStringWithFormat(NSLocalizedString("Invalid response: %@", comment: "Invalid runtime response error"), reason)
        case .startFailed(let reason):
            return String.localizedStringWithFormat(NSLocalizedString("Failed to start container: %@", comment: "Container start error"), reason)
        case .stopFailed(let reason):
            return String.localizedStringWithFormat(NSLocalizedString("Failed to stop container: %@", comment: "Container stop error"), reason)
        case .deleteFailed(let reason):
            return String.localizedStringWithFormat(NSLocalizedString("Failed to delete container: %@", comment: "Container delete error"), reason)
        case .imageNotAvailable(let image):
            return String.localizedStringWithFormat(NSLocalizedString("Image not available: %@", comment: "Image unavailable error"), image)
        }
    }
}
