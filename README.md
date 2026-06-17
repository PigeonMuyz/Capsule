# Capsule

<div align="center">

**基于 Apple Containerization Framework 的原生 macOS 容器管理器**

像 OrbStack 一样管理容器和镜像，完全原生，完全 Swift。

[开发路线图](ROADMAP.md) • [Phase 1 总结](PHASE1_SUMMARY.md)

</div>

---

## 🎯 项目定位

Capsule 是一个原生 macOS 容器管理工具，直接使用 **Apple Containerization framework** 创建、运行、管理 Linux 容器。

**不是什么**：
- ❌ 不是 Docker Desktop 的替代品
- ❌ 不是 Apple `container` CLI 的图形壳
- ❌ 不调用 `container` 命令行工具

**是什么**：
- ✅ 直接使用 Apple Containerization Swift API
- ✅ 原生 macOS 体验
- ✅ SwiftUI + Swift Concurrency
- ✅ App Sandbox 沙盒化

## ✨ 特性

### 当前实现（Phase 1 MVP）

- ✅ 完整的 SwiftUI 界面
- ✅ 容器生命周期管理（创建、启动、停止、删除）
- ✅ 实时日志查看（stdout/stderr 分流）
- ✅ 日志搜索和过滤
- ✅ 容器资源配置（CPU、内存）
- ✅ 容器详情查看

### 规划中

- 📋 Phase 2: 状态持久化（App 重启后恢复）
- 📋 Phase 3: Agent 架构（后台运行容器）
- 📋 Phase 4: 镜像管理（拉取、删除、缓存）
- 📋 Phase 5: 高级功能（挂载、环境变量、自动启动）

详见 [ROADMAP.md](ROADMAP.md)

## 🚀 快速开始

### 系统要求

- **必需**：
  - Apple Silicon Mac (M1/M2/M3/M4)
  - macOS 26 或更高版本
  - Xcode 26 或更高版本
  - Apple Developer Account（本地测试可用免费账号）

### 编译和运行

1. **克隆仓库**
   ```bash
   git clone https://github.com/PigeonMuyz/Capsule.git
   cd Capsule
   ```

2. **打开 Xcode 项目**
   ```bash
   open Capsule.xcodeproj
   ```

3. **等待依赖下载**
   - Xcode 会自动下载 Apple Containerization Swift Package
   - 首次下载可能需要几分钟

4. **选择 Mac 目标并运行**
   - 在 Xcode 顶部选择 "Capsule" scheme
   - 选择 "My Mac" 作为目标设备
   - 点击 ▶️ 运行（或按 ⌘R）

### 当前状态说明

⚠️ **重要**：当前版本的容器操作是**模拟**的。要运行真实的 Linux 容器，还需要：

1. **准备 Linux Kernel**
   - 从 Apple Containerization 仓库获取
   - 或自行编译适用于 Apple Silicon 的内核

2. **准备测试镜像**
   - 下载 OCI 镜像（如 alpine:latest）
   - 转换为 EXT4 rootfs

3. **集成真实 API**
   - 在 `RuntimeCore.swift` 中完成 `// TODO:` 标记的部分
   - 连接真实的容器 stdout/stderr

详见 [PHASE1_SUMMARY.md](PHASE1_SUMMARY.md) 的"待完成的集成工作"部分。

## 📁 项目结构

```
Capsule/
├── Capsule/
│   ├── Models/
│   │   └── ContainerModels.swift      # 数据模型
│   ├── Runtime/
│   │   └── RuntimeCore.swift          # 容器运行时核心
│   ├── Services/
│   │   └── LogService.swift           # 日志服务
│   ├── ViewModels/
│   │   └── ContainerViewModel.swift   # ViewModel
│   ├── Views/
│   │   ├── ContainersListView.swift   # 容器列表
│   │   ├── CreateContainerView.swift  # 创建容器
│   │   └── ContainerLogsView.swift    # 日志查看
│   ├── ContentView.swift              # 主应用
│   └── Capsule.entitlements           # 权限配置
├── Capsule.xcodeproj/                 # Xcode 项目
├── ROADMAP.md                         # 开发路线图
├── PHASE1_SUMMARY.md                  # Phase 1 总结
└── README.md                          # 本文档
```

## 🛠️ 技术栈

- **语言**：Swift 6.2+
- **UI 框架**：SwiftUI
- **并发**：Swift Concurrency (async/await, Actor)
- **容器框架**：Apple Containerization
  - `Containerization` - 核心容器管理
  - `ContainerizationOCI` - OCI 镜像支持
  - `ContainerizationEXT4` - EXT4 文件系统
  - `ContainerizationExtras` - 额外工具
- **日志**：OSLog (Unified Logging)
- **架构**：MVVM + Actor Model

## 📊 统计

- **Swift 文件**：8 个
- **代码行数**：~1,580 行
- **实现时间**：Phase 1 完成于 2026-06-17

## 🤝 贡献

欢迎贡献！项目当前处于 MVP 阶段，后续阶段会持续开发。

### 开发原则

1. ✅ **必须**通过 Apple Containerization framework 操作容器
2. ❌ **禁止**调用 Apple `container` CLI 工具
3. ❌ **禁止**连接系统 `container-apiserver`
4. ✅ **必须**维护独立的状态和存储
5. ✅ **必须**使用 App Sandbox

## 📄 许可

MIT License

## 🙏 致谢

- [Apple Containerization](https://github.com/apple/containerization) - 核心容器框架
- Apple Virtualization Framework - VM 支持

---

**开发状态**: Phase 1 (MVP) ✅ 已完成架构和 UI | 等待 Containerization API 集成

**作者**: PigeonMuyz  
**最后更新**: 2026-06-17
