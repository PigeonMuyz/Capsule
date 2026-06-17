# Capsule UI 改进计划

**参考**: OrbStack 的 UI 设计  
**目标**: 提供更专业、更易用的容器管理界面

---

## 🎨 当前 UI 问题

### 问题 1: 容器列表布局简陋
- ❌ 使用 Table 视图，信息密集但不够直观
- ❌ 没有按状态分组（Running/Stopped）
- ❌ 操作按钮混在一起，不够清晰

### 问题 2: 详情面板不够完整
- ❌ 只有 Overview 和 Logs 两个标签
- ❌ 缺少 Terminal、Files、Stats 等功能
- ❌ 信息展示不够结构化

### 问题 3: 导航结构单一
- ❌ 只有 Containers/Images/Settings 三个入口
- ❌ 没有 Volumes、Networks 等重要功能
- ❌ 缺少分类和层级

---

## 🎯 改进目标

### 1. 侧边栏导航（参考 OrbStack）

```
Docker
  📦 Containers
  🖼️ Images  
  💾 Volumes
  🌐 Networks

General
  ⚙️ Settings
  📊 Activity Monitor
```

### 2. 容器列表视图

**分组显示**：
- Running (2)
  - postgres-bookshelf [绿色指示器]
  - redis-bookshelf [绿色指示器]

- Stopped (0)
  - [空状态提示]

**容器卡片**：
```
┌─────────────────────────────────────────┐
│ 🟢 postgres-bookshelf                   │
│ docker.io/library/postgres:14-alpine    │
│ 4 CPUs · 1GB RAM · 192.168.64.3        │
│ [▶️ Start] [⏹️ Stop] [🗑️ Delete]       │
└─────────────────────────────────────────┘
```

### 3. 容器详情面板

**顶部操作栏**：
- 容器名称和状态
- 快速操作按钮：Start/Stop/Restart/Delete

**标签页**：
1. **Info** - 基本信息
   - ID、名称、镜像
   - 资源配置（CPU、内存）
   - 网络信息（IP、端口映射）
   - 挂载点

2. **Logs** - 日志查看
   - 实时日志流
   - 搜索和过滤
   - 导出功能

3. **Terminal** - 终端访问
   - Shell 接入
   - 命令执行

4. **Files** - 文件浏览
   - 容器文件系统浏览
   - 文件上传/下载

5. **Stats** - 资源监控
   - CPU 使用率
   - 内存使用率
   - 网络 I/O

---

## 📋 实施计划

### Phase 1: 改进容器列表（优先级：高）

**任务**：
1. ✅ 修复停止容器不显示的问题（已完成）
2. 将 Table 改为卡片式列表
3. 按状态分组（Running/Stopped）
4. 优化状态指示器
5. 改进操作按钮布局

**文件**：
- `ContainersListView.swift`

**预计时间**: 2-3 小时

### Phase 2: 完善详情面板（优先级：高）

**任务**：
1. 重新设计详情页布局
2. 添加 Terminal 标签（集成 shell）
3. 添加 Stats 标签（资源监控）
4. 改进 Info 标签的信息展示
5. 优化 Logs 标签的 UI

**文件**：
- `ContainerLogsView.swift` → `ContainerDetailView.swift`
- 新增 `ContainerTerminalView.swift`
- 新增 `ContainerStatsView.swift`

**预计时间**: 4-5 小时

### Phase 3: 重构导航结构（优先级：中）

**任务**：
1. 添加分组导航（Docker/General）
2. 添加 Volumes 页面
3. 添加 Networks 页面
4. 添加 Activity Monitor

**文件**：
- `ContentView.swift`
- 新增 `VolumesView.swift`
- 新增 `NetworksView.swift`

**预计时间**: 3-4 小时

### Phase 4: Images 页面（优先级：中）

**任务**：
1. 实现镜像列表显示
2. 添加镜像拉取功能
3. 添加镜像删除功能
4. 显示镜像大小和标签

**文件**：
- 新增 `ImagesView.swift`
- `RuntimeCore.swift` 添加镜像管理方法

**预计时间**: 3-4 小时

---

## 🚀 快速原型

### 改进后的容器列表代码结构

```swift
struct ContainersListView: View {
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            toolbar
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Running 分组
                    if !runningContainers.isEmpty {
                        containerGroup(
                            title: "Running",
                            count: runningContainers.count,
                            containers: runningContainers
                        )
                    }
                    
                    // Stopped 分组
                    if !stoppedContainers.isEmpty {
                        containerGroup(
                            title: "Stopped",
                            count: stoppedContainers.count,
                            containers: stoppedContainers
                        )
                    }
                }
                .padding()
            }
        }
    }
    
    func containerCard(_ container: ContainerSummary) -> some View {
        HStack {
            statusIndicator(container.status)
            VStack(alignment: .leading) {
                Text(container.name).font(.headline)
                Text(container.image).font(.caption)
                HStack {
                    Label("\(container.cpus) CPUs", systemImage: "cpu")
                    Label(container.memoryDisplayString, systemImage: "memorychip")
                }
                .font(.caption2)
            }
            Spacer()
            actionButtons(container)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}
```

---

## 🎨 设计参考

### 颜色方案
- **Running**: 绿色 (#34C759)
- **Stopped**: 灰色 (#8E8E93)
- **Failed**: 红色 (#FF3B30)
- **Starting**: 黄色 (#FFCC00)

### 图标
- Containers: `cube.fill`
- Images: `photo.stack.fill`
- Volumes: `externaldrive.fill`
- Networks: `network`
- Settings: `gearshape.fill`

---

## ✅ 立即行动

**建议优先实施 Phase 1**（改进容器列表），因为：
1. 影响最直接，用户立即能感受到改进
2. 工作量适中，2-3 小时可完成
3. 为后续改进打下基础

**需要我现在开始实施 Phase 1 吗？**

---

**创建日期**: 2026-06-17  
**参考**: OrbStack UI 设计
