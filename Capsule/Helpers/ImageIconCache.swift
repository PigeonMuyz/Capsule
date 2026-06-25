import SwiftUI
import Foundation
import Combine

/// 镜像图标缓存管理器
@MainActor
class ImageIconCache: ObservableObject {
    static let shared = ImageIconCache()

    @Published private var iconCache: [String: NSImage] = [:]
    private var loadingTasks: [String: Task<NSImage?, Never>] = [:]

    private init() {
        loadCacheFromDisk()
    }

    /// 获取镜像图标（如果没有则返回 nil，会异步加载）
    func getIcon(for repository: String) -> NSImage? {
        let key = cacheKey(for: repository)

        // 如果已经在缓存中，直接返回
        if let cached = iconCache[key] {
            return cached
        }

        // 如果正在加载，不重复发起请求
        if loadingTasks[key] != nil {
            return nil
        }

        // 异步加载图标
        let task = Task {
            await fetchIcon(for: repository, key: key)
        }
        loadingTasks[key] = task

        return nil
    }

    /// 从 Docker Hub 获取图标
    private func fetchIcon(for repository: String, key: String) async -> NSImage? {
        defer {
            loadingTasks.removeValue(forKey: key)
        }

        // 提取镜像名称（去除 tag）
        let imageName = extractImageName(from: repository)

        // 尝试从 Docker Hub API 获取图标
        if let icon = await fetchDockerHubIcon(imageName: imageName) {
            iconCache[key] = icon
            saveToDisk(icon: icon, key: key)
            return icon
        }

        return nil
    }

    /// 从 Docker Hub API 获取镜像图标
    private func fetchDockerHubIcon(imageName: String) async -> NSImage? {
        // Docker Hub 官方镜像 API
        let namespace: String
        let name: String

        if imageName.contains("/") {
            let parts = imageName.split(separator: "/", maxSplits: 1)
            namespace = String(parts[0])
            name = String(parts[1])
        } else {
            namespace = "library"
            name = imageName
        }

        guard let url = URL(string: "https://hub.docker.com/v2/repositories/\(namespace)/\(name)/") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            // 解析 JSON 获取图标 URL
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let logoURL = json["logo_url"] as? [String: Any],
               let large = logoURL["large"] as? String,
               let iconURL = URL(string: large) {

                // 下载图标
                let (iconData, _) = try await URLSession.shared.data(from: iconURL)
                return NSImage(data: iconData)
            }
        } catch {
            // 静默失败，使用占位符
            return nil
        }

        return nil
    }

    /// 提取镜像名称（去除 registry 前缀和 tag）
    private func extractImageName(from repository: String) -> String {
        var name = repository

        // 移除 registry 前缀
        if name.hasPrefix("docker.io/library/") {
            name = String(name.dropFirst("docker.io/library/".count))
        } else if name.hasPrefix("docker.io/") {
            name = String(name.dropFirst("docker.io/".count))
        } else if name.hasPrefix("ghcr.io/") {
            name = String(name.dropFirst("ghcr.io/".count))
        } else if name.hasPrefix("gcr.io/") {
            name = String(name.dropFirst("gcr.io/".count))
        }

        return name
    }

    /// 生成缓存 key
    private func cacheKey(for repository: String) -> String {
        let imageName = extractImageName(from: repository)
        return imageName.replacingOccurrences(of: "/", with: "_")
    }

    // MARK: - 磁盘缓存

    private var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Capsule")
            .appendingPathComponent("ImageIcons")
    }

    private func loadCacheFromDisk() {
        guard let cacheDir = cacheDirectory else { return }

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files where file.pathExtension == "png" {
            let key = file.deletingPathExtension().lastPathComponent
            if let image = NSImage(contentsOf: file) {
                iconCache[key] = image
            }
        }
    }

    private func saveToDisk(icon: NSImage, key: String) {
        guard let cacheDir = cacheDirectory,
              let tiffData = icon.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return
        }

        let fileURL = cacheDir.appendingPathComponent("\(key).png")
        try? pngData.write(to: fileURL)
    }
}
