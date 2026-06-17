import Foundation
import OSLog

private let logger = Logger(subsystem: "io.github.pigeonmuyz.capsule", category: "logs")

/// Service for managing container logs
actor LogService {
    // MARK: - Properties

    private let maxLinesPerContainer = 1000
    private var logs: [String: RingBuffer] = [:]
    private var streams: [String: AsyncStream<LogLine>.Continuation] = [:]

    // MARK: - Ring Buffer

    private struct RingBuffer {
        private var lines: [LogLine] = []
        private let maxSize: Int

        init(maxSize: Int) {
            self.maxSize = maxSize
        }

        mutating func append(_ line: LogLine) {
            lines.append(line)
            if lines.count > maxSize {
                lines.removeFirst()
            }
        }

        func getAll() -> [LogLine] {
            return lines
        }

        func getLast(_ count: Int) -> [LogLine] {
            let startIndex = max(0, lines.count - count)
            return Array(lines[startIndex...])
        }

        mutating func clear() {
            lines.removeAll()
        }
    }

    // MARK: - Public Methods

    /// Append a log line for a container
    /// - Parameters:
    ///   - containerID: Container ID
    ///   - stream: Log stream (stdout/stderr)
    ///   - content: Log content
    func appendLog(containerID: String, stream: LogLine.LogStream, content: String) {
        let logLine = LogLine(timestamp: Date(), stream: stream, content: content)

        // Store in ring buffer
        if logs[containerID] == nil {
            logs[containerID] = RingBuffer(maxSize: maxLinesPerContainer)
        }
        logs[containerID]?.append(logLine)

        // Emit to active streams
        streams[containerID]?.yield(logLine)

        logger.debug("Log appended for container \(containerID): [\(stream.rawValue)] \(content)")
    }

    /// Get recent logs for a container
    /// - Parameters:
    ///   - containerID: Container ID
    ///   - limit: Maximum number of lines to return (default: 100)
    /// - Returns: Array of log lines
    func getRecentLogs(containerID: String, limit: Int = 100) -> [LogLine] {
        guard let buffer = logs[containerID] else {
            return []
        }
        return buffer.getLast(limit)
    }

    /// Get all logs for a container
    /// - Parameter containerID: Container ID
    /// - Returns: Array of log lines
    func getAllLogs(containerID: String) -> [LogLine] {
        guard let buffer = logs[containerID] else {
            return []
        }
        return buffer.getAll()
    }

    /// Stream logs for a container
    /// - Parameter containerID: Container ID
    /// - Returns: AsyncStream of log lines
    func streamLogs(containerID: String) -> AsyncStream<LogLine> {
        return AsyncStream { continuation in
            // Store continuation for this container
            streams[containerID] = continuation

            // Send existing logs first
            if let buffer = logs[containerID] {
                for line in buffer.getAll() {
                    continuation.yield(line)
                }
            }

            // Handle stream termination
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeStream(containerID: containerID)
                }
            }
        }
    }

    /// Clear logs for a container
    /// - Parameter containerID: Container ID
    func clearLogs(containerID: String) {
        logs[containerID]?.clear()
        logger.info("Logs cleared for container \(containerID)")
    }

    /// Remove all logs and streams for a container (called when container is deleted)
    /// - Parameter containerID: Container ID
    func removeContainer(containerID: String) {
        logs.removeValue(forKey: containerID)
        streams[containerID]?.finish()
        streams.removeValue(forKey: containerID)
        logger.info("Logs removed for container \(containerID)")
    }

    // MARK: - Private Helpers

    private func removeStream(containerID: String) {
        streams.removeValue(forKey: containerID)
    }
}

// MARK: - Log Utilities

extension LogService {
    /// Parse container output and append to logs
    /// - Parameters:
    ///   - containerID: Container ID
    ///   - data: Raw output data
    ///   - stream: Log stream (stdout/stderr)
    func appendOutput(containerID: String, data: Data, stream: LogLine.LogStream) {
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }

        // Split by newlines and append each line
        let lines = text.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            appendLog(containerID: containerID, stream: stream, content: line)
        }
    }

    /// Simulate log output for testing (will be removed when real container integration is done)
    func simulateLog(containerID: String, message: String, stream: LogLine.LogStream = .stdout) {
        appendLog(containerID: containerID, stream: stream, content: message)
    }
}
