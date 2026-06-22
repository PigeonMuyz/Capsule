import Foundation

actor LogCacheStore {
    static let shared = LogCacheStore()

    struct Entry: Codable, Identifiable, Hashable {
        let id: UUID
        let timestamp: Date
        let content: String

        init(id: UUID = UUID(), timestamp: Date = Date(), content: String) {
            self.id = id
            self.timestamp = timestamp
            self.content = content
        }
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let directory: URL

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("Capsule/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func entries(for containerID: String, retention: LogRetentionPolicy) -> [Entry] {
        let trimmed = trimmedEntries(readEntries(for: containerID), retention: retention)
        writeEntries(trimmed, for: containerID)
        return trimmed
    }

    func append(_ entry: Entry, for containerID: String, retention: LogRetentionPolicy) {
        var entries = readEntries(for: containerID)
        if entries.last?.content == entry.content {
            return
        }
        entries.append(entry)
        writeEntries(trimmedEntries(entries, retention: retention), for: containerID)
    }

    func clear(containerID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: containerID))
    }

    private func readEntries(for containerID: String) -> [Entry] {
        let url = fileURL(for: containerID)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return content
            .split(separator: "\n")
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(Entry.self, from: data)
            }
    }

    private func writeEntries(_ entries: [Entry], for containerID: String) {
        let payload = entries.compactMap { entry -> String? in
            guard let data = try? encoder.encode(entry) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        .joined(separator: "\n")

        try? payload.write(to: fileURL(for: containerID), atomically: true, encoding: .utf8)
    }

    private func trimmedEntries(_ entries: [Entry], retention: LogRetentionPolicy) -> [Entry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retention.days, to: Date()) ?? .distantPast
        let byDate = entries.filter { $0.timestamp >= cutoff }
        guard byDate.count > retention.maxEntries else { return byDate }
        return Array(byDate.suffix(retention.maxEntries))
    }

    private func fileURL(for containerID: String) -> URL {
        let safeID = containerID.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }
        return directory.appendingPathComponent(String(safeID)).appendingPathExtension("jsonl")
    }
}

struct LogRetentionPolicy: Hashable {
    var days: Int
    var maxEntries: Int

    static let defaultDays = 7
    static let defaultMaxEntries = 2_000
    static let defaultPolicy = LogRetentionPolicy(days: defaultDays, maxEntries: defaultMaxEntries)

    static func load(containerID: String) -> LogRetentionPolicy {
        let defaults = UserDefaults.standard
        let days = defaults.integer(forKey: daysKey(containerID))
        let maxEntries = defaults.integer(forKey: maxEntriesKey(containerID))
        return LogRetentionPolicy(
            days: days > 0 ? days : defaultDays,
            maxEntries: maxEntries > 0 ? maxEntries : defaultMaxEntries
        )
    }

    func save(containerID: String) {
        UserDefaults.standard.set(days, forKey: Self.daysKey(containerID))
        UserDefaults.standard.set(maxEntries, forKey: Self.maxEntriesKey(containerID))
    }

    private static func daysKey(_ containerID: String) -> String {
        "logRetentionDays.\(containerID)"
    }

    private static func maxEntriesKey(_ containerID: String) -> String {
        "logRetentionMaxEntries.\(containerID)"
    }
}
