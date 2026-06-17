# Capsule 开发路线图

## 🎯 项目目标

**一句话定位**：像 OrbStack 一样的原生 macOS 容器管理器，基于 Apple Containerization Framework

**最终效果**：
- ✅ 通过 GUI 管理 Apple Container（容器生命周期：创建、启动、停止、删除）
- ✅ 管理容器镜像（浏览、拉取、删除）
- ✅ 配置容器参数（CPU、内存、挂载目录、环境变量、命令）
- ✅ 实时查看容器日志
- ✅ 持久化容器配置，App 重启后恢复状态
- ✅ 后台运行容器，不依赖前台 UI

**技术约束**：
- ⚠️ 必须使用 Apple Containerization Swift Package API
- ⚠️ 禁止调用 `container` CLI 工具
- ⚠️ 不接管系统已有容器

---

## 📊 功能优先级

### P0 - 核心能力（MVP）

| 功能 | 说明 | 状态 |
|------|------|------|
| 容器生命周期 | 创建、启动、停止、删除容器 | ⚪ 待开发 |
| 容器列表 | 显示所有容器及其状态 | ⚪ 待开发 |
| 基础配置 | CPU、内存、命令、工作目录 | ⚪ 待开发 |
| 日志查看 | 实时显示 stdout/stderr | ⚪ 待开发 |
| 本地镜像 | 使用已准备好的测试镜像 | ⚪ 待开发 |

### P1 - 持久化与后台

| 功能 | 说明 | 状态 |
|------|------|------|
| 状态持久化 | 保存容器配置和历史 | ⚪ 待开发 |
| Agent 架构 | UI 与 Runtime 分离 | ⚪ 待开发 |
| 后台运行 | App 退出后容器继续运行 | ⚪ 待开发 |

### P2 - 镜像管理

| 功能 | 说明 | 状态 |
|------|------|------|
| 镜像列表 | 显示本地缓存的镜像 | ⚪ 待开发 |
| 镜像拉取 | 从 registry 拉取镜像 | ⚪ 待开发 |
| 拉取进度 | 显示下载进度 | ⚪ 待开发 |
| 镜像删除 | 清理不需要的镜像 | ⚪ 待开发 |

### P3 - 高级配置

| 功能 | 说明 | 状态 |
|------|------|------|
| 目录挂载 | 挂载 macOS 目录到容器 | ⚪ 待开发 |
| 环境变量 | 配置容器环境变量 | ⚪ 待开发 |
| 容器详情页 | 查看完整配置和运行信息 | ⚪ 待开发 |
| 日志搜索 | 搜索和过滤日志 | ⚪ 待开发 |

### P4 - 用户体验

| 功能 | 说明 | 状态 |
|------|------|------|
| 菜单栏图标 | 快速访问和状态提示 | ⚪ 待规划 |
| 容器自动启动 | App 启动时自动启动指定容器 | ⚪ 待规划 |
| 容器模板 | 快速创建常用容器配置 | ⚪ 待规划 |
| Shell 接入 | 一键进入容器 shell | ⚪ 待规划 |

---

## 🗓️ 开发阶段

### 阶段 1：MVP 原型（2-3 周）

**目标**：验证技术可行性，实现最小可用容器管理

**核心任务**：
1. 配置项目 entitlements（App Sandbox + Virtualization）
2. 集成 Apple Containerization Swift Package
3. 实现 `RuntimeCore` Actor
   - 初始化 ContainerManager（kernel + network + rosetta）
   - 封装容器创建、启动、停止、删除 API
4. 实现基础 UI
   - 容器列表视图（表格：名称、状态、镜像、操作按钮）
   - 创建容器表单（名称、镜像、CPU、内存、命令）
   - 日志查看器（实时滚动）
5. 实现日志服务
   - 捕获容器 stdout/stderr
   - Ring buffer（最近 1000 行）

**验收标准**：
- ✅ 能通过 GUI 创建一个 alpine 容器
- ✅ 运行 `/bin/sh -c "echo hello"` 并在 UI 显示输出
- ✅ 能停止容器
- ✅ 能删除容器并清理 rootfs
- ✅ 全程不调用 `container` CLI

---

### 阶段 2：持久化（1-2 周）

**目标**：App 重启后能恢复容器列表和配置

**核心任务**：
1. 引入 SwiftData 或 SQLite
2. 设计数据模型
   - `Container`：id, name, image, status, config, created_at
   - `LogEntry`（可选）：container_id, timestamp, stream, line
3. 实现状态存储层 `StateStore`
4. 容器生命周期与数据库同步
5. App 启动时加载历史容器

**验收标准**：
- ✅ App 重启后能看到之前创建的容器
- ✅ 已停止的容器可以重新启动
- ✅ 删除容器后数据库记录被清理

---

### 阶段 3：App/Agent 架构（2-3 周）

**目标**：容器独立于 UI 运行，实现后台持续运行

**核心任务**：
1. 创建 `CapsuleAgent` target（LaunchAgent）
2. 将 `RuntimeCore` 迁移到 Agent
3. 定义 XPC 协议
   ```swift
   protocol CapsuleXPCProtocol {
       func createContainer(spec: Data, reply: @escaping (Data?, Error?) -> Void)
       func startContainer(id: String, reply: @escaping (Error?) -> Void)
       func stopContainer(id: String, reply: @escaping (Error?) -> Void)
       func deleteContainer(id: String, reply: @escaping (Error?) -> Void)
       func listContainers(reply: @escaping (Data?, Error?) -> Void)
       func streamLogs(id: String, reply: @escaping (Data?, Error?) -> Void)
   }
   ```
4. 实现 XPC Server（Agent 侧）
5. 实现 XPC Client（App 侧）
6. 状态订阅与日志流转发

**验收标准**：
- ✅ Capsule.app 退出后容器继续运行
- ✅ 重新打开 App 能自动重连 Agent
- ✅ 能订阅正在运行容器的日志流

---

### 阶段 4：镜像管理（2-3 周）

**目标**：从 registry 拉取真实镜像，管理本地镜像缓存

**核心任务**：
1. 实现 `ImageService`
   - 使用 `ContainerizationOCI` API
   - 解析 image reference（如 `nginx:alpine`）
   - 拉取 manifest + layers
   - 进度回调
2. 实现 `RootfsService`
   - 基于 image layers 创建 EXT4 rootfs
   - 管理 rootfs 生命周期
3. 镜像列表 UI
   - 显示已缓存镜像
   - 镜像拉取界面（输入 reference + 进度条）
   - 镜像删除
4. 改进容器创建表单
   - 镜像选择器（本地镜像 + 输入新 reference）

**验收标准**：
- ✅ 能输入 `nginx:alpine` 并拉取
- ✅ 能看到本地缓存的所有镜像
- ✅ 能删除不需要的镜像
- ✅ 能用拉取的镜像创建容器

---

### 阶段 5：高级配置（2-3 周）

**目标**：完善容器配置能力，接近生产可用

**核心任务**：
1. 实现 `MountService`
   - 目录选择对话框（security-scoped bookmark）
   - bookmark 持久化和恢复
   - 转换为 Containerization mount config
2. 容器创建向导增强
   - 挂载配置（host path → guest path，read-only 选项）
   - 环境变量配置（key-value 列表）
   - 高级选项（Rosetta、自动启动）
3. 容器详情页
   - Tabs：Overview / Logs / Config / Mounts / Environment
   - 显示运行时信息（状态、资源、启动时间、退出码）
4. 日志增强
   - 搜索和过滤
   - 导出日志

**验收标准**：
- ✅ 能选择 macOS 目录挂载到容器
- ✅ 能配置环境变量
- ✅ 挂载目录在容器重启后仍有效
- ✅ 能创建运行实际服务的容器（如 web server）

---

## 🛠️ 技术架构

```
Capsule.app (SwiftUI)
  ├─ ContainersView (容器列表)
  ├─ CreateContainerView (创建向导)
  ├─ ContainerDetailView (容器详情)
  ├─ ImagesView (镜像列表)
  └─ XPCClient (通信层)
       ↓ XPC
CapsuleAgent (LaunchAgent)
  ├─ XPCServer
  ├─ RuntimeCore (Actor)
  ├─ ImageService
  ├─ RootfsService
  ├─ MountService
  ├─ LogService
  └─ StateStore (SwiftData/SQLite)
       ↓
Apple Containerization Framework
  ├─ Containerization
  ├─ ContainerizationOCI
  ├─ ContainerizationEXT4
  └─ ContainerizationExtras
```

---

## 📝 核心数据模型

```swift
struct ContainerSpec: Codable {
    var id: String
    var name: String
    var image: String              // reference 或 digest
    var cpus: Int                  // 默认 2
    var memoryBytes: UInt64        // 默认 2GB
    var rootfsSizeBytes: UInt64    // 默认 10GB
    var command: [String]          // 启动命令
    var workingDirectory: String   // 工作目录
    var environment: [String: String]
    var mounts: [MountSpec]
    var rosettaEnabled: Bool       // 支持 amd64
    var autostart: Bool
}

struct MountSpec: Codable {
    var hostBookmarkID: String     // security-scoped bookmark
    var guestPath: String
    var readOnly: Bool
}

enum ContainerStatus: String, Codable {
    case creating
    case created
    case starting
    case running
    case stopping
    case stopped
    case failed
}
```

---

## ⚠️ 关键约束

### 必须遵守
- ✅ 所有容器操作通过 `Containerization` framework API
- ✅ 启用 App Sandbox
- ✅ 配置 `com.apple.security.virtualization` entitlement
- ✅ 用户目录挂载必须通过 security-scoped bookmark

### 严格禁止
- ❌ 使用 `Process` 调用 `container` CLI
- ❌ 解析 `container list --format json`
- ❌ 连接系统 `com.apple.container.apiserver`
- ❌ 默认挂载用户 Home/Documents/Downloads
- ❌ 明文存储 registry token

---

## 🎯 里程碑

| 里程碑 | 目标 | 预计时间 |
|--------|------|---------|
| **M1** | 完成 MVP，验证技术可行性 | Week 3 |
| **M2** | 完成持久化，App 重启恢复状态 | Week 5 |
| **M3** | 完成 Agent 架构，后台运行 | Week 8 |
| **M4** | 完成镜像管理，拉取真实镜像 | Week 11 |
| **M5** | 完成高级配置，接近生产可用 | Week 14 |

---

## 📚 开发环境

**必需**：
- Apple Silicon Mac (M1/M2/M3/M4)
- macOS 26 (首选)
- Xcode 26
- Swift 6.2+
- Apple Developer Account（本地测试可用免费账号）

**依赖**：
```swift
.package(
    url: "https://github.com/apple/containerization.git",
    revision: "<specific-commit-sha>"  // 锁定版本
)
```

---

**最后更新**：2026-06-17  
**当前阶段**：准备开始阶段 1（MVP 原型）
