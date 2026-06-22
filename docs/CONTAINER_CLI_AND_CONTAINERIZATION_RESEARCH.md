# container CLI 与 Containerization 研究笔记

日期：2026-06-18

本笔记用于 Capsule 后续开发辅助，不作为用户文档发布。

## 环境快照

- 本机 CLI：`/usr/local/bin/container`
- 版本：`container CLI version 1.0.0 (build: release, commit: ee848e3)`
- Capsule 当前 SwiftPM 依赖：
  - `https://github.com/apple/containerization.git`
  - branch: `main`
  - revision: `d55cc188ce0dcf183b1f659e8a0da3234c233076`
- Xcode 本地源码缓存：
  - `~/Library/Developer/Xcode/DerivedData/Capsule-ajckjcmdojrhrlfuzwmarcjdrimq/SourcePackages/checkouts/containerization`

## container CLI 命令总览

`container --help` 暴露的顶层能力可分为容器、镜像、机器、卷、网络、builder、system 几组。

### 容器命令

| 命令 | 用途 | 对 Capsule 的意义 |
| --- | --- | --- |
| `container create <image> [arguments...]` | 创建容器但不启动 | 可用于未来“创建容器”表单 |
| `container run <image> [arguments...]` | 创建并运行容器 | 可用于快速运行镜像 |
| `container start [--attach] [--interactive] <container-id>` | 启动已存在容器 | 现有启动按钮使用 |
| `container stop [--all] [--signal <signal>] [--time <time>] [ids...]` | 停止容器 | 现有停止按钮使用 |
| `container kill [--all] [--signal <signal>] [ids...]` | 发送信号杀掉容器 | 适合做“强制停止”二级操作 |
| `container delete` / `container rm` | 删除容器 | 删除操作需确认 |
| `container list` / `container ls` | 列出容器 | 主列表数据源 |
| `container inspect <container-ids>...` | 查看容器详情 | Info 页数据源 |
| `container logs [--boot] [--follow] [-n <n>] <container-id>` | 查看日志 | 注意使用 `-n`，没有 `--tail` |
| `container exec [options] <container-id> <arguments>...` | 在容器中执行命令 | Terminal、Files 浏览、文件操作数据源 |
| `container copy` / `container cp` | 主机和容器之间复制文件 | 外部编辑器同步需要它 |
| `container export [-o output] <id>` | 导出容器文件系统 | 可做备份/导出功能 |
| `container stats [--format ...] [--no-stream] [containers...]` | 查看资源统计 | 可做实时 CPU/内存/网络面板 |
| `container prune` | 清理停止容器 | 高风险，需明确确认 |

`create` / `run` 的重要参数：

- 进程：`--env`、`--env-file`、`--gid`、`--uid`、`--user`、`--workdir`、`--ulimit`、`-i`、`-t`
- 资源：`--cpus`、`--memory`
- 镜像/平台：`--arch`、`--os`、`--platform`、`--max-concurrent-downloads`
- 容器配置：`--name`、`--entrypoint`、`--init`、`--label`、`--read-only`、`--rm`、`--rosetta`、`--runtime`、`--ssh`
- 网络/DNS：`--network`、`--dns`、`--dns-domain`、`--dns-option`、`--dns-search`、`--no-dns`
- 端口/Socket：`--publish` / `-p`、`--publish-socket`
- 文件系统：`--mount`、`--volume` / `-v`、`--tmpfs`、`--shm-size`
- 权限：`--cap-add`、`--cap-drop`

### 镜像命令

`container image` / `container i` 暴露：

- `delete` / `rm`
- `inspect`
- `list` / `ls`
- `load`
- `prune`
- `pull`
- `push`
- `save`
- `tag`

建议 Capsule 优先补齐：

- `image inspect`：镜像详情页。
- `image pull`：拉取镜像进度和失败提示。
- `image save/load`：导入导出镜像。
- `image tag`：镜像重命名/重新打标。
- `image prune`：高风险清理操作，需要二次确认。

### Registry 命令

`container registry` / `container r` 暴露：

- `login`
- `logout`
- `list` / `ls`

这部分适合以后做 Registry 账户管理。当前阶段不建议优先做，因为涉及凭据存储、Keychain、错误恢复和多 registry UX。

### Machine 命令

`container machine` / `container m` 暴露：

- `create`
- `delete` / `rm`
- `inspect`
- `list` / `ls`
- `logs`
- `run`
- `set`
- `set-default`
- `stop`

这些命令看起来对应 Apple CLI 管理的 Linux machine 生命周期。Capsule 当前 README 已声明不初始化 Container CLI，因此 app 内也应该避免隐式执行 machine 初始化；可以做只读状态展示、手动启动/停止已有 machine，或引导用户先安装并初始化 Apple Container。

### Volume 命令

`container volume` / `container v` 暴露：

- `create`
- `delete` / `rm`
- `list` / `ls`
- `inspect`
- `prune`

Capsule 适合做：

- 卷列表。
- 卷详情。
- 创建/删除卷。
- prune 作为高风险操作。

### Network 命令

`container network` / `container n` 暴露：

- `create`
- `delete` / `rm`
- `list` / `ls`
- `inspect`
- `prune`

Capsule 适合做：

- 网络列表。
- 网络详情。
- 创建/删除网络。
- prune 作为高风险操作。

### Builder 命令

`container builder` 暴露：

- `start`
- `status`
- `stop`
- `delete` / `rm`

这部分可以作为未来镜像构建能力的前置状态面板。短期如果没有 build UI，可以只在错误提示里检测 builder 状态。

### System 命令

`container system` / `container s` 暴露：

- `df`
- `dns`
- `kernel`
- `logs`
- `property`
- `start`
- `status`
- `stop`
- `version`

Capsule 可优先使用：

- `system status`：诊断 Container 是否可用。
- `system version`：关于页/诊断包。
- `system df`：磁盘占用。
- `system logs`：开发诊断。

`system stop` 属于高影响操作，不应放在常规 UI 中。

## CLI 行为细节

### JSON 输出

已验证：

- `container list --format json`
- `container image list --format json`
- `container stats --no-stream --format json`

`stats --no-stream --format json` 返回数组，字段示例：

- `id`
- `cpuUsageUsec`
- `memoryUsageBytes`
- `memoryLimitBytes`
- `networkRxBytes`
- `networkTxBytes`
- `blockReadBytes`
- `blockWriteBytes`
- `numProcesses`

### 日志

本机 CLI 的日志命令不支持 Docker 风格的 `--tail`。

正确写法：

```bash
container logs -n 200 <container-id>
container logs --follow -n 200 <container-id>
```

错误写法：

```bash
container logs --tail 200 <container-id>
```

这会报：

```text
Unknown option '--tail'
Usage: container logs [--boot] [--follow] [-n <n>] [--debug] <container-id>
```

### Files 浏览

`container` 没有独立的文件浏览命令。当前可行方案是通过 `exec` 调 Linux 命令：

```bash
container exec <container-id> ls -la <path>
container exec <container-id> rm -rf <path>
```

如果要做可靠的 Finder 列表模式，建议不要长期解析普通 `ls -la` 文本；更稳的方式是在容器内执行 shell 脚本输出 JSON Lines，例如读取：

- 文件名
- 类型
- 权限
- owner/group
- size
- mtime
- symlink target

删除文件仍可通过 `exec rm`，但 UI 必须确认路径、避免空路径和 `/`。

### 文件复制与外部编辑器

主机和容器之间复制使用：

```bash
container copy <container-id>:<remote-path> <local-path>
container copy <local-path> <container-id>:<remote-path>
```

外部编辑器保存监听可以采用：

1. 容器文件复制到 app 临时目录。
2. `NSWorkspace` 打开本地副本。
3. 轮询本地文件 `modificationDate`。
4. 变化后复制回容器。

当前这种方案不依赖 inotify，也不要求容器里安装额外服务。

### 插件结构

本机 `/usr/local/libexec/container/plugins` 下有：

- `container-core-images`
- `container-network-vmnet`
- `container-runtime-linux`
- `machine-apiserver`

各插件有 `config.toml`，其中 `machine-apiserver` 描述为：

```text
Container machine management API plugin
```

这说明 `container machine` 不是普通子命令实现，而是主 CLI + 插件/XPC 服务组合。

注意：虽然 `container image --help` 能列出 image 子命令，但本机直接执行 `container image pull --help` 或 `container help image pull` 会失败，报 plugin lookup 相关错误。因此后续如果要自动枚举每个二级命令的完整参数，不要只依赖嵌套 `--help`；应结合：

- 顶层 group help。
- 实际命令试探。
- 插件目录和插件服务能力。
- Apple 上游文档/源码。

## Containerization 依赖研究

### 包结构

`containerization` 的 `Package.swift` 暴露多个库和一个示例/工具可执行文件：

- `Containerization`
- `ContainerizationOCI`
- `ContainerizationEXT4`
- `ContainerizationNetlink`
- `ContainerizationIO`
- `ContainerizationOS`
- `ContainerizationExtras`
- `ContainerizationArchive`
- `VminitdCore`
- `cctl`

包最低平台是 macOS 15.0，但部分网络能力在源码中判断了 macOS 26。

### 可以脱离 CLI 运行容器吗？

可以，但不是“直接接管系统 container CLI 的容器”。

关键类型：

- `ContainerManager`
- `LinuxContainer`
- `LinuxPod`
- `ImageStore`
- `VZVirtualMachineManager`
- `VirtualMachineInstance`

`ContainerManager` 可以直接创建 `LinuxContainer`。它需要：

- Linux kernel：`Kernel(path:platform:)`
- initfs：`initfsReference: "vminit:latest"` 或 `Mount`
- 镜像引用：例如 `docker.io/library/alpine:latest`
- 可选网络：例如 macOS 26+ 的 `VmnetNetwork()`
- rootfs/writable layer 大小
- CPU、内存、mount、process、DNS、hosts 等配置

源码里的 `Sources/cctl/RunCommand.swift` 就是直接使用 SDK 运行容器的证据。核心流程是：

1. 创建 `Kernel`。
2. 创建 `ContainerManager(kernel:initfsReference:network:rosetta:)`。
3. 调 `manager.create(...)` 得到 `LinuxContainer`。
4. 调 `container.create()` 启动底层 VM 并配置 runtime。
5. 调 `container.start()` 启动容器 init 进程。
6. 调 `container.wait()` 等待退出。
7. 调 `container.stop()` 清理。

`LinuxContainer` 还提供：

- `stop()`
- `kill(_:)`
- `wait(timeoutInSeconds:)`
- `resize(to:)`
- `exec(...)`
- `withVirtualMachineInstance(...)`

`LinuxPod` 是更接近“一个 VM 内多个容器”的实验 API。它提供：

- `addContainer(...)`
- `create()`
- `startContainer(...)`
- `stopContainer(...)`
- `killContainer(...)`
- `waitContainer(...)`
- `resizeContainer(...)`
- `execInContainer(...)`
- `listContainers()`
- `statistics(...)`
- `withVirtualMachineInstance(...)`

这意味着如果 Capsule 以后想做“自己的容器运行时”，SDK 路线是可行的。

### 可以脱离 CLI 管理 machine 吗？

结论：可以用 SDK 创建和控制底层 VM，但没有看到等价于 `container machine` 的高层 machine manager API。

已看到的 VM 相关抽象：

- `VirtualMachineManager`：协议，只有 `create(config:)`。
- `VZVirtualMachineManager`：Virtualization.framework backed 实现。
- `VirtualMachineInstance`：提供 start/stop/pause/resume 等实例生命周期。
- `VZVirtualMachineInstance`：具体 VM 实现。

这适合开发“Capsule 自己的 VM/Pod/Container 运行环境”，但不等价于调用 Apple CLI 当前的 machine 数据库和 machine API。

本机 CLI 的 machine 能力来自 `/usr/local/libexec/container/plugins/machine-apiserver`，它是 XPC 服务插件。`containerization` 包中没有发现同名的高层 machine API。也就是说：

- 如果目标是管理用户已经用 Apple CLI 创建的 machine，短期继续走 CLI 更稳。
- 如果目标是 Capsule 自己创建一个运行 Linux 容器的 VM，可以用 `VZVirtualMachineManager` / `LinuxPod` / `LinuxContainer` 自己实现。

### 不是 CLI 的 drop-in replacement

`ImageStore.default` 默认目录是当前用户 Application Support 下的：

```text
com.apple.containerization
```

而 Apple CLI/runtime 是插件和系统服务组合，命令路径、插件路径、服务名和 machine API 都不只是 `containerization` 这个 Swift 包。直接用 SDK 创建出来的容器大概率是 Capsule 自己管理的状态，不会自然出现在：

```bash
container list
container machine list
```

除非 Capsule 复用/对接 Apple CLI 的服务层、状态目录和 XPC API。这个方向需要额外逆向/研究，不建议作为第一阶段架构。

## 对 Capsule 的建议

### 短期：继续以 CLI 为主

适合当前产品阶段：

- 管理用户已经安装和初始化的 Apple Container。
- 兼容 `container list`、`inspect`、`logs`、`exec`、`copy`、`stats`。
- 避免 Capsule 自己分发 kernel/initfs 和维护 VM runtime。

短期应补强：

- 更完整的错误提示：未安装 CLI、未初始化 machine、system 未启动。
- `system status` 诊断入口。
- stats 面板。
- image/volume/network 详情。
- 高风险操作确认。

### 中期：把 SDK 作为“原生运行时”实验

如果希望 Capsule 不依赖 `container` CLI，可以做一个独立模式：

- System Containers：通过 Apple CLI 管理系统已有容器。
- Capsule Native Containers：通过 `containerization` SDK 创建 app 自己的容器/Pod。

这样不会混淆两套状态来源。

原生运行时必须解决：

- kernel 获取与更新。
- `vminit:latest` initfs 获取与版本管理。
- 镜像存储目录与迁移。
- 网络能力和 macOS 版本差异。
- VM 生命周期、崩溃恢复、日志、文件、端口、卷。
- app 沙盒、权限、签名和分发。
- 与 CLI 容器不互通时的 UI 解释。

### 不建议现在做的事

- 不建议直接把 `containerization` 当作现有 CLI 的内部 API 替换。
- 不建议在 UI 中自动初始化或重建 Apple Container machine。
- 不建议默认暴露 `prune`、`system stop`、`delete --all` 这类高影响命令。
- 不建议让文件浏览长期依赖不可控的 `ls -la` 文本格式。

## 后续开发清单

优先级较高：

- `container system status` 和 `system version` 接入诊断页。
- `container stats --no-stream --format json` 接入资源卡片。
- Info 页继续完善 Ports、Mounts、Env、Command、Created/Started、Resources。
- Files 改为 JSON Lines 输出，减少 `ls` 解析风险。
- 文件删除和覆盖写回增加更严格路径保护。
- 日志缓存继续使用 `container logs -n`，不要使用 `--tail`。

优先级中等：

- 镜像 inspect/save/load/tag。
- volume inspect。
- network inspect。
- builder status。

实验方向：

- 用 `ContainerManager` 做一个最小 SDK proof-of-concept：
  - 指定 kernel 路径。
  - 拉取/读取 `alpine`。
  - 创建容器。
  - 执行 `/bin/sh -c "echo hello"`。
  - 收集 stdout/stderr。
  - 停止并删除运行态。
- 用 `LinuxPod` 验证一个 VM 内多容器和 `statistics(...)`。
- 明确 SDK-created 容器是否、以及怎样能和 Apple CLI 状态互通。

