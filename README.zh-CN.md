# Capsule

[English](README.md) | 简体中文 | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md)

Capsule 是一款原生 macOS 应用，用来通过一个清爽的桌面界面管理 Apple containers。

它把系统 `container` 运行时包装成 SwiftUI 体验：容器、镜像、卷、网络、Linux machines、日志、文件、统计信息、Shell 入口和 Docker 风格导入，都集中在一个紧凑的窗口里。

## 为什么是 Capsule

Apple 的容器工具很强，但日常使用时常常需要一个可视化界面：查看正在运行的容器、停止占用资源的容器、打开日志、拉取镜像，或者把熟悉的 `docker run` 命令转换成 Apple container 运行时可以使用的配置。

Capsule 就是这个工作流上的轻量原生外壳。这个名字很直白：每个容器都像一个 capsule，你可以检查、启动、停止、打开或移除它，而不用离开 macOS。

## 功能

- 管理容器：列表、创建、启动、停止、删除、查看详情和刷新。
- 查看运行时信息：状态、镜像、CPU、内存、运行时长、日志、统计信息、文件浏览器和终端入口。
- 管理镜像：列出、拉取、查看和删除本地镜像。
- 在独立的原生界面中管理卷和网络。
- 管理由 Apple container 工具支持的 Linux machines。
- 导入 Docker 工作流：
  - 解析 `docker run` 命令。
  - 解析 Docker Compose 服务。
  - Compose 项目的启动、停止、删除、依赖顺序和分组日志。
- 原生 macOS 设置，用于运行时行为和外部终端偏好。
- 通过 `Localizable.xcstrings` 提供本地化 UI 字符串。

## 系统要求

- macOS 26.0 或更高版本。
- 从源码构建需要 Xcode 26 或更高版本。
- 已安装 Apple container 工具，并且可通过 `/usr/local/bin/container` 访问。
- 当前 Apple container 技术栈推荐使用 Apple Silicon Mac。

Capsule 暂时不提供 Container CLI 的安装、引导或初始化能力。请先自行安装并初始化 Apple container 工具：

- [apple/container](https://github.com/apple/container)

启动 Capsule 前，请先在终端确认 container 运行时可用：

```bash
/usr/local/bin/container system status
/usr/local/bin/container list --all
```

如果系统没有运行，可以执行：

```bash
/usr/local/bin/container system start
```

Capsule 也可以配置为随应用启动和停止 container system。

## 构建

克隆项目并用 Xcode 打开：

```bash
git clone https://github.com/PigeonMuyz/Capsule.git
cd Capsule
open Capsule.xcodeproj
```

然后选择 `Capsule` scheme，并在 `My Mac` 上运行。

Xcode 会自动解析 Swift Package 依赖，包括 Apple 的 `containerization` package。

## 项目结构

```text
Capsule/
├── Capsule/
│   ├── Models/          # 容器和日志模型
│   ├── Runtime/         # RuntimeCore 与 container CLI 桥接
│   ├── Services/        # Docker / Compose 解析和项目逻辑
│   ├── ViewModels/      # 可观察的应用状态
│   ├── Views/           # SwiftUI 界面和详情面板
│   ├── ContentView.swift
│   └── Localizable.xcstrings
├── Capsule.xcodeproj
└── README.md
```

## 技术栈

- Swift 和 SwiftUI。
- Swift Concurrency，包含 actors 和 async/await。
- Apple Containerization Swift packages。
- Apple `container` CLI 集成。
- OSLog 运行时诊断。

## 说明

Capsule 是 Apple container 生态的实验性原生客户端。应用会跟随已安装的 `container` 命令行为和 JSON 输出，因此当 Apple 工具链演进时，部分界面可能需要同步调整。

## 许可证

Capsule 使用 MIT License 发布。详见 [LICENSE](LICENSE)。
