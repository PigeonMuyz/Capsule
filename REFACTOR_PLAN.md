# Capsule 完整重构计划

## 设计原则

### Apple Container CLI 原生功能
基于 `container --help` 的实际命令，原生支持：

**容器操作：**
- `container create` - 创建容器
- `container run` - 运行容器
- `container start/stop/kill` - 启动/停止/杀死容器
- `container delete/rm` - 删除容器
- `container list/ls` - 列出容器
- `container inspect` - 查看容器详情
- `container logs` - 查看容器日志
- `container exec` - 在容器中执行命令
- `container stats` - 查看容器资源统计
- `container copy/cp` - 容器文件复制
- `container export` - 导出容器文件系统
- `container prune` - 清理停止的容器

**镜像操作：**
- `container image list/ls` - 列出镜像
- `container image pull/push` - 拉取/推送镜像
- `container image delete/rm` - 删除镜像
- `container image inspect` - 查看镜像详情
- `container image tag` - 标记镜像
- `container image save/load` - 保存/加载镜像
- `container image prune` - 清理未使用的镜像
- `container build` - 构建镜像（支持 Dockerfile/Containerfile）

**卷操作：**
- `container volume list/ls` - 列出卷
- `container volume create` - 创建卷
- `container volume delete/rm` - 删除卷
- `container volume inspect` - 查看卷详情
- `container volume prune` - 清理未引用的卷

**网络操作：**
- `container network list/ls` - 列出网络
- `container network create` - 创建网络
- `container network delete/rm` - 删除网络
- `container network inspect` - 查看网络详情
- `container network prune` - 清理未连接的网络

**虚拟机（Machine）操作：**
- `container machine list/ls` - 列出虚拟机
- `container machine create` - 创建虚拟机
- `container machine delete/rm` - 删除虚拟机
- `container machine inspect` - 查看虚拟机详情
- `container machine run` - 在虚拟机中运行命令
- `container machine stop` - 停止虚拟机
- `container machine set` - 设置虚拟机配置
- `container machine set-default` - 设置默认虚拟机
- `container machine logs` - 查看虚拟机日志

**系统操作：**
- `container system` - 系统管理

**构建器操作：**
- `container builder` - 构建器管理

**注册表操作：**
- `container registry` - 注册表登录管理

### Capsule 软件增强功能（非 CLI 原生）

1. **Restart 策略守护进程** - 监控容器状态并按策略自动重启
   - 策略：no, always, on-failure, unless-stopped
   - 由 `RestartDaemon` 实现
   
2. **Startup（容器自启动）** - 应用启动时自动启动指定容器
   - 由 `ContainerViewModel` + `UserDefaults` 实现
   - 存储容器的自启动配置
   
3. **Compose 支持** - 解析 docker-compose.yml 并转换为 Container CLI 命令
   - 由 `ComposeManager` 实现
   - 多容器项目管理
   - 服务编排

4. **Docker Run 导入** - 解析 `docker run` 命令转换为 Container CLI
   - 由 `DockerCommandParser` 实现
   - 多行命令支持（反斜杠续行）

---

## UI 架构：NavigationSplitView 三段式布局

```
┌─────────────┬──────────────────┬─────────────────────────────┐
│   Sidebar   │   List Column    │      Detail Panel          │
│             │                  │                             │
│ Containers  │  容器列表         │  ┌─ TabView ─────────────┐ │
│ Images      │  (卡片形式)      │  │ Overview │ Logs │ ...  │ │
│ Volumes     │                  │  └──────────────────────────┘│
│ Networks    │                  │                             │
│ Machines    │                  │      Tab 内容区域           │
│             │                  │                             │
└─────────────┴──────────────────┴─────────────────────────────┘
```

---

## 详细重构任务

### 1. Containers 视图重构

**List Column (中间栏):**
- 保持现有的分组布局（Running / Projects / Stopped）
- 使用 OrbStack 风格的卡片设计
- 显示容器名称、镜像、状态

**Detail Panel (右侧栏 - 使用 TabView):**

**Tab 1: Overview**
- 容器基本信息（名称、ID、镜像、状态、创建时间）
- 资源配置（CPUs、Memory）
- 操作按钮（Start/Stop、Restart、Delete）
- **Capsule 增强**：Restart Policy（守护进程）、Startup（自启动）配置

**Tab 2: Inspect**
- 完整的 `container inspect` 输出
- Command、Arguments、Workdir
- Mounts（卷挂载）
- Ports（端口映射）
- Environment Variables

**Tab 3: Logs**
- 实时日志显示
- 使用 `container logs --follow`
- 支持清空、复制

**Tab 4: Stats**
- 资源使用统计
- 使用 `container stats`
- CPU、内存、网络、磁盘 I/O

**Tab 5: Terminal**
- 在 Terminal.app 中打开 `container exec`
- 交互式 shell

**Tab 6: Files**
- 容器文件系统浏览
- 支持 `container copy` 复制文件

---

### 2. Images 视图重构

**List Column:**
- 镜像列表（Repository:Tag）
- 显示大小、创建时间
- 卡片样式

**Detail Panel (TabView):**

**Tab 1: Overview**
- 基本信息（Repository、Tag、ID、Size、Created）
- 操作按钮（Pull、Push、Tag、Delete、Save）
- 快速创建容器按钮

**Tab 2: Layers**
- 镜像层信息
- 使用 `container image inspect` 解析层级

**Tab 3: History**
- 镜像构建历史
- 显示每一层的命令

---

### 3. Volumes 视图重构

**List Column:**
- 卷列表
- 显示名称、挂载点、大小
- 卡片样式

**Detail Panel (TabView):**

**Tab 1: Overview**
- 基本信息（名称、创建时间、挂载路径）
- 操作按钮（Delete、Prune）
- 引用的容器列表

**Tab 2: Files**
- 浏览卷内文件
- 文件树形结构

---

### 4. Networks 视图重构

**List Column:**
- 网络列表
- 显示名称、驱动类型
- 卡片样式

**Detail Panel (TabView):**

**Tab 1: Overview**
- 基本信息（名称、Driver、Subnet）
- 操作按钮（Delete、Prune）
- 连接的容器列表

**Tab 2: Connected Containers**
- 详细显示所有连接的容器
- IP 地址分配情况

---

### 5. Machines 视图重构

**List Column:**
- 虚拟机列表
- 显示名称、状态、资源配置
- 卡片样式

**Detail Panel (TabView):**

**Tab 1: Overview**
- 基本信息（名称、镜像、状态、IP 地址）
- 资源配置（CPUs、Memory、Disk）
- 操作按钮（Start、Stop、Delete、Set Config）

**Tab 2: Console**
- 在 Terminal.app 中打开 `container machine run`
- 交互式 shell 访问

**Tab 3: Logs**
- 使用 `container machine logs`
- 查看虚拟机启动日志

---

### 6. AddContainerView 重构（新建容器）

使用 **TabView** 替代现有的 Mode Picker：

**Tab 1: Configure（手动配置）**
- 基于 `container create` / `container run` 的原生参数
- 基本设置：名称、镜像、命令
- 资源：CPUs、Memory
- 网络：端口映射、网络选择
- 存储：卷挂载
- 环境变量
- **Capsule 增强**：
  - Restart Policy（守护进程自动重启）
  - Startup（应用启动时自动启动）

**Tab 2: Docker Run Import**
- 粘贴 `docker run` 命令
- 使用 `DockerCommandParser` 解析
- 支持多行命令（反斜杠续行）
- 解析后自动填充到 Configure tab
- 显示解析结果预览

**Tab 3: Compose**
- 粘贴或选择 `docker-compose.yml` 文件
- 使用 `ComposeManager` 解析
- 显示服务列表
- **Capsule 增强**：项目级别的启动/停止管理
- 创建后在 Containers 列表中显示为 Projects 组

---

## 实现顺序

1. ✅ 先重构 **ContainerDetailPanel**，使用原生 `TabView` 替代自定义 `TabButton`
2. ✅ 重构 **AddContainerView**，改为 TabView 结构，清晰标注增强功能
3. ✅ 重构 **ImagesView** 详情面板
4. ✅ 重构 **VolumesView** 详情面板
5. ✅ 重构 **NetworksView** 详情面板
6. ✅ 重构 **MachinesView** 详情面板
7. ✅ 统一所有卡片样式和 hover 效果

---

## 视觉设计统一

- 所有列表项使用 OrbStack 风格的圆角卡片
- Hover 时显示操作按钮
- 选中时显示蓝色边框
- 所有 Detail Panel 使用原生 SwiftUI `TabView`
- Tab 样式统一，使用系统原生的 `.tabViewStyle(.automatic)`

---

## 代码规范

- 所有 CLI 调用通过 `RuntimeCore` 统一管理
- 增强功能（Restart、Startup、Compose）单独标注
- 使用 `// MARK: - Apple Container CLI Native` 和 `// MARK: - Capsule Enhancement` 区分代码块
- 保持三段式布局：`NavigationSplitView(sidebar, content, detail)`
