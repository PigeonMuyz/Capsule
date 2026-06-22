import Foundation
import OSLog

private let logger = Logger(subsystem: "io.github.pigeonmuyz.capsule", category: "compose-parser")

/// Parse docker-compose.yml files and convert to Compose projects
struct DockerComposeParser {

    // MARK: - Main Parsing

    /// Parse a docker-compose.yml file content
    static func parse(yamlContent: String, appName: String? = nil) throws -> ParsedCompose {
        let yaml = try parseYAML(yamlContent)

        guard let root = yaml as? [String: Any] else {
            throw ParseError.invalidFormat("Root must be a dictionary")
        }

        // Parse services
        var services: [ComposeService] = []
        if let servicesDict = root["services"] as? [String: Any] {
            for (serviceName, serviceData) in servicesDict {
                if let service = try? parseService(name: serviceName, data: serviceData) {
                    services.append(service)
                }
            }
        }

        // Parse volumes
        var volumes: [String] = []
        if let volumesDict = root["volumes"] as? [String: Any] {
            volumes = Array(volumesDict.keys)
        }

        // Parse networks
        var networks: [String] = []
        if let networksDict = root["networks"] as? [String: Any] {
            networks = Array(networksDict.keys)
        }

        let projectName = appName ?? "compose-\(UUID().uuidString.prefix(8))"

        return ParsedCompose(
            name: projectName,
            services: services,
            volumes: volumes,
            networks: networks
        )
    }

    // MARK: - Service Parsing

    private static func parseService(name: String, data: Any) throws -> ComposeService {
        guard let serviceDict = data as? [String: Any] else {
            throw ParseError.invalidService(name)
        }

        // Required: image
        guard let image = serviceDict["image"] as? String else {
            throw ParseError.missingImage(name)
        }
        let containerName = serviceDict["container_name"] as? String ?? name
        let restartPolicy = serviceDict["restart"] as? String
        let hasHealthcheck = serviceDict["healthcheck"] != nil

        // Optional: ports
        var ports: [(host: Int, container: Int)] = []
        var portBindings: [String] = []
        if let portsArray = serviceDict["ports"] as? [Any] {
            for port in portsArray {
                if let portString = port as? String {
                    portBindings.append(portString)
                    if let parsed = parsePortMapping(portString) {
                        ports.append(parsed)
                    }
                } else if let portDict = port as? [String: Any] {
                    let target = stringValue(portDict["target"])
                    let published = stringValue(portDict["published"])
                    let hostIP = stringValue(portDict["host_ip"])
                    let protocolValue = stringValue(portDict["protocol"])
                    let rendered = [hostIP, published, target]
                        .compactMap { value in value?.isEmpty == false ? value : nil }
                        .joined(separator: ":")
                    if !rendered.isEmpty {
                        portBindings.append(protocolValue.map { "\(rendered)/\($0)" } ?? rendered)
                    }
                    if let host = Int(published ?? ""), let container = Int(target ?? "") {
                        ports.append((host, container))
                    }
                }
            }
        }

        // Optional: volumes
        var volumes: [String] = []
        if let volumesArray = serviceDict["volumes"] as? [Any] {
            for volume in volumesArray {
                if let volumeString = volume as? String {
                    volumes.append(volumeString)
                }
            }
        }

        // Optional: environment
        var environment: [String: String] = [:]
        if let envArray = serviceDict["environment"] as? [Any] {
            for env in envArray {
                if let envString = env as? String {
                    let parts = envString.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        environment[String(parts[0])] = String(parts[1])
                    }
                }
            }
        } else if let envDict = serviceDict["environment"] as? [String: Any] {
            for (key, value) in envDict {
                environment[key] = "\(value)"
            }
        }

        // Optional: depends_on
        var dependsOn: [String] = []
        if let dependsArray = serviceDict["depends_on"] as? [Any] {
            dependsOn = dependsArray.compactMap { $0 as? String }
        } else if let dependsDict = serviceDict["depends_on"] as? [String: Any] {
            dependsOn = Array(dependsDict.keys)
        }

        var networks: [String] = []
        if let networkArray = serviceDict["networks"] as? [Any] {
            networks = networkArray.compactMap { $0 as? String }
        } else if let networkDict = serviceDict["networks"] as? [String: Any] {
            networks = Array(networkDict.keys)
        }

        // Optional: resources
        var cpus = 2
        var memoryGB = 2

        if let deploy = serviceDict["deploy"] as? [String: Any],
           let resources = deploy["resources"] as? [String: Any],
           let limits = resources["limits"] as? [String: Any] {
            if let cpusValue = limits["cpus"] as? String {
                cpus = Int(Double(cpusValue) ?? 2.0)
            } else if let cpusValue = limits["cpus"] as? Double {
                cpus = Int(cpusValue)
            }

            if let memory = limits["memory"] as? String {
                memoryGB = parseMemoryString(memory)
            }
        }

        // Optional: command
        var command: [String] = []
        if let commandString = serviceDict["command"] as? String {
            command = commandString.split(separator: " ").map(String.init)
        } else if let commandArray = serviceDict["command"] as? [Any] {
            command = commandArray.compactMap { $0 as? String }
        }

        return ComposeService(
            name: name,
            containerName: containerName,
            image: image,
            ports: ports,
            portBindings: portBindings,
            volumes: volumes,
            environment: environment,
            dependsOn: dependsOn,
            networks: networks,
            restartPolicy: restartPolicy,
            healthcheck: hasHealthcheck,
            cpus: cpus,
            memoryGB: memoryGB,
            command: command
        )
    }

    // MARK: - Helper Parsers

    private static func parsePortMapping(_ portString: String) -> (host: Int, container: Int)? {
        let parts = portString.split(separator: ":")
        if parts.count >= 2 {
            if let host = Int(parts[parts.count - 2]),
               let container = Int(parts[parts.count - 1]) {
                return (host, container)
            }
        }
        return nil
    }

    private static func parseMemoryString(_ memory: String) -> Int {
        var value = memory.uppercased()
        var multiplier = 1

        if value.hasSuffix("G") || value.hasSuffix("GB") {
            value = value.replacingOccurrences(of: "GB", with: "").replacingOccurrences(of: "G", with: "")
            multiplier = 1
        } else if value.hasSuffix("M") || value.hasSuffix("MB") {
            value = value.replacingOccurrences(of: "MB", with: "").replacingOccurrences(of: "M", with: "")
            multiplier = 1024
        }

        let numValue = Int(Double(value) ?? 2.0)
        return max(1, numValue / multiplier)
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let int as Int:
            return String(int)
        case let double as Double:
            return String(Int(double))
        default:
            return nil
        }
    }

    // MARK: - Simple YAML Parser

    private static func parseYAML(_ content: String) throws -> Any {
        var result: [String: Any] = [:]
        var currentPath: [String] = []
        var dictStack: [[String: Any]] = []

        let lines = content.components(separatedBy: .newlines)
        var index = 0
        var blockPath: [String]?
        var blockStyle: String?
        var blockIndent = 0
        var blockLines: [String] = []

        func flushBlock() {
            guard let path = blockPath else { return }
            let joined: String
            if blockStyle == "|" {
                joined = blockLines.joined(separator: "\n")
            } else {
                joined = blockLines
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            setNestedValue(&result, path: path, value: joined)
            blockPath = nil
            blockStyle = nil
            blockLines = []
        }

        while index < lines.count {
            let line = lines[index]
            // Skip empty lines and comments
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count

            if blockPath != nil {
                if trimmed.isEmpty {
                    blockLines.append("")
                    index += 1
                    continue
                }
                if indent > blockIndent {
                    blockLines.append(String(line.dropFirst(min(line.count, blockIndent + 2))))
                    index += 1
                    continue
                }
                flushBlock()
                continue
            }

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }

            // Calculate indentation level
            let level = indent / 2

            if trimmed.hasPrefix("- ") {
                // Array item. Handle this before key/value parsing because
                // Compose values often contain ':' inside strings, e.g.
                // "${SERVER_PORT:-8080}:8080".
                let value = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                let parsedValue = parseValue(value)

                var array = getNestedValue(result, path: currentPath) as? [Any] ?? []
                array.append(parsedValue)
                setNestedValue(&result, path: currentPath, value: array)
            } else if let colonIndex = trimmed.firstIndex(of: ":") {
                // Parse key-value
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let valueStart = trimmed.index(after: colonIndex)
                let value = valueStart < trimmed.endIndex
                    ? String(trimmed[valueStart...]).trimmingCharacters(in: .whitespaces)
                    : ""

                // Adjust path based on level
                while currentPath.count > level {
                    currentPath.removeLast()
                    if !dictStack.isEmpty {
                        dictStack.removeLast()
                    }
                }

                if value == ">" || value == "|" {
                    blockPath = currentPath + [key]
                    blockStyle = value
                    blockIndent = indent
                    blockLines = []
                } else if value.isEmpty {
                    // This is a dictionary key
                    currentPath.append(key)
                    dictStack.append([:])
                } else {
                    // This is a value
                    let parsedValue = parseValue(value)
                    setNestedValue(&result, path: currentPath + [key], value: parsedValue)
                }
            }

            index += 1
        }

        flushBlock()

        return result
    }

    private static func parseValue(_ value: String) -> Any {
        // Try to parse as number
        if let intValue = Int(value) {
            return intValue
        }
        if let doubleValue = Double(value) {
            return doubleValue
        }

        // Boolean
        if value.lowercased() == "true" {
            return true
        }
        if value.lowercased() == "false" {
            return false
        }

        // Remove quotes
        var cleanValue = value
        if (cleanValue.hasPrefix("\"") && cleanValue.hasSuffix("\"")) ||
           (cleanValue.hasPrefix("'") && cleanValue.hasSuffix("'")) {
            cleanValue = String(cleanValue.dropFirst().dropLast())
        }

        return cleanValue
    }

    private static func setNestedValue(_ dict: inout [String: Any], path: [String], value: Any) {
        guard !path.isEmpty else { return }

        if path.count == 1 {
            dict[path[0]] = value
            return
        }

        let key = path[0]
        var nested = dict[key] as? [String: Any] ?? [:]
        setNestedValue(&nested, path: Array(path.dropFirst()), value: value)
        dict[key] = nested
    }

    private static func getNestedValue(_ dict: [String: Any], path: [String]) -> Any? {
        guard !path.isEmpty else { return nil }

        if path.count == 1 {
            return dict[path[0]]
        }

        if let nested = dict[path[0]] as? [String: Any] {
            return getNestedValue(nested, path: Array(path.dropFirst()))
        }

        return nil
    }

    // MARK: - Types

    struct ParsedCompose {
        let name: String
        let services: [ComposeService]
        let volumes: [String]
        let networks: [String]
    }

    typealias ComposeService = ComposeProject.ComposeService

    // MARK: - Example Generator

    static func exampleComposeYAML() -> String {
        return """
        version: '3.8'

        services:
          web:
            image: nginx:latest
            ports:
              - "8080:80"
            volumes:
              - web-data:/usr/share/nginx/html
            depends_on:
              - api

          api:
            image: node:18-alpine
            ports:
              - "3000:3000"
            environment:
              - NODE_ENV=production
              - DB_HOST=db
            depends_on:
              - db

          db:
            image: postgres:14-alpine
            volumes:
              - db-data:/var/lib/postgresql/data
            environment:
              - POSTGRES_PASSWORD=secret
              - POSTGRES_DB=myapp

        volumes:
          web-data:
          db-data:

        networks:
          default:
            driver: bridge
        """
    }

    enum ParseError: Error, LocalizedError {
        case invalidFormat(String)
        case invalidService(String)
        case missingImage(String)

        var errorDescription: String? {
            switch self {
            case .invalidFormat(let msg):
                return "Invalid YAML format: \(msg)"
            case .invalidService(let name):
                return "Invalid service configuration: \(name)"
            case .missingImage(let name):
                return "Service '\(name)' is missing required 'image' field"
            }
        }
    }
}
