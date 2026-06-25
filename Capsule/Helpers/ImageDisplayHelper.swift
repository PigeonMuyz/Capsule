import SwiftUI

/// 处理镜像显示的辅助函数
struct ImageDisplayHelper {

    /// 简化镜像仓库名称显示
    static func simplifyRepository(_ repository: String) -> String {
        // Docker Hub official images: docker.io/library/xxx -> xxx
        if repository.hasPrefix("docker.io/library/") {
            return String(repository.dropFirst("docker.io/library/".count))
        }

        // Docker Hub user images: docker.io/username/xxx -> username/xxx
        if repository.hasPrefix("docker.io/") {
            return String(repository.dropFirst("docker.io/".count))
        }

        // GitHub Container Registry: ghcr.io/xxx -> xxx
        if repository.hasPrefix("ghcr.io/") {
            return String(repository.dropFirst("ghcr.io/".count))
        }

        // Google Container Registry: gcr.io/xxx -> xxx
        if repository.hasPrefix("gcr.io/") {
            return String(repository.dropFirst("gcr.io/".count))
        }

        // 其他保持原样
        return repository
    }

    /// 获取镜像的 Registry 标签
    static func getRegistryBadge(_ repository: String) -> String? {
        if repository.hasPrefix("docker.io/") {
            return "Docker Hub"
        }

        if repository.hasPrefix("ghcr.io/") {
            return "GitHub"
        }

        if repository.hasPrefix("gcr.io/") {
            return "GCR"
        }

        return nil
    }

    /// 获取标签颜色
    static func getBadgeColor(_ repository: String) -> Color {
        if repository.hasPrefix("docker.io/") {
            return .blue
        }

        if repository.hasPrefix("ghcr.io/") {
            return .purple
        }

        if repository.hasPrefix("gcr.io/") {
            return .green
        }

        return .gray
    }

    /// 根据镜像名称获取对应的 SF Symbol 图标
    static func getImageIcon(_ imageName: String) -> String {
        let lowercased = imageName.lowercased()

        // 数据库
        if lowercased.contains("postgres") || lowercased.contains("postgresql") {
            return "cylinder.split.1x2"
        }
        if lowercased.contains("mysql") || lowercased.contains("mariadb") {
            return "cylinder.split.1x2"
        }
        if lowercased.contains("mongo") {
            return "leaf"
        }
        if lowercased.contains("redis") {
            return "rectangle.stack"
        }

        // Web 服务器
        if lowercased.contains("nginx") {
            return "server.rack"
        }
        if lowercased.contains("apache") || lowercased.contains("httpd") {
            return "server.rack"
        }

        // 编程语言
        if lowercased.contains("python") {
            return "chevron.left.forwardslash.chevron.right"
        }
        if lowercased.contains("node") {
            return "chevron.left.forwardslash.chevron.right"
        }
        if lowercased.contains("golang") || lowercased.contains("go") {
            return "chevron.left.forwardslash.chevron.right"
        }
        if lowercased.contains("java") {
            return "cup.and.saucer"
        }

        // 操作系统
        if lowercased.contains("ubuntu") || lowercased.contains("debian") ||
           lowercased.contains("alpine") || lowercased.contains("centos") {
            return "cube"
        }

        // 默认图标
        return "photo"
    }

    /// 获取图标颜色
    static func getImageIconColor(_ imageName: String) -> Color {
        let lowercased = imageName.lowercased()

        if lowercased.contains("postgres") {
            return .blue
        }
        if lowercased.contains("mysql") {
            return .orange
        }
        if lowercased.contains("mongo") {
            return .green
        }
        if lowercased.contains("redis") {
            return .red
        }
        if lowercased.contains("nginx") {
            return .green
        }
        if lowercased.contains("python") {
            return .blue
        }
        if lowercased.contains("node") {
            return .green
        }
        if lowercased.contains("golang") || lowercased.contains("go") {
            return .cyan
        }

        return .blue
    }
}
