# Docker 兼容功能实现指南

## 📋 功能概述

Capsule 现在支持导入 Docker 命令和 Docker Compose 文件，自动转换为 Apple Container 命令。

## 🎯 支持的功能

### 1. Docker Run 命令转换

**支持的参数：**
- `--name` - 容器名称
- `-p, --publish` - 端口映射（如 `-p 8080:80`）
- `-v, --volume` - 卷挂载（如 `-v data:/data`）
- `-e, --env` - 环境变量（如 `-e NODE_ENV=production`）
- `--cpus` - CPU 限制
- `-m, --memory` - 内存限制（支持 `2g`, `512m` 等格式）
- `-d, --detach` - 后台运行（自动处理）
- `-it` - 交互式（自动处理）

**示例：**
```bash
docker run -d --name my-nginx -p 8080:80 -v web-data:/usr/share/nginx/html nginx:latest
```

转换为：
```bash
container volume create web-data
container create --name my-nginx --cpus 2 --memory 2GB nginx:latest
container start my-nginx
```

### 2. Docker Compose 支持

**支持的字段：**
- `services` - 服务定义
  - `image` - 镜像名称
  - `ports` - 端口映射
  - `volumes` - 卷挂载
  - `environment` - 环境变量
  - `depends_on` - 依赖关系
- `volumes` - 命名卷
- `networks` - 网络定义

**示例 docker-compose.yml：**
```yaml
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
```

## 🚀 使用方法

### 在 UI 中导入

1. 点击容器列表页面的 **"Import"** 按钮
2. 选择导入类型：
   - **Docker Run** - 粘贴单个 `docker run` 命令
   - **Docker Compose** - 粘贴完整的 `docker-compose.yml` 内容
3. 点击 **"Import"** 按钮
4. Capsule 会自动创建所需的容器、卷和网络

### 通过代码使用

```swift
// 解析 Docker Run 命令
let command = "docker run -d --name my-app -p 3000:3000 node:18"
let spec = try DockerCommandParser.parseDockerRun(command)
await viewModel.createContainer(spec: spec)

// 解析 Docker Compose 文件
let yaml = String(contentsOf: composeFileURL)
let app = try DockerComposeParser.parse(yamlContent: yaml, appName: "my-stack")
let specs = DockerComposeParser.toContainerSpecs(app)
for spec in specs {
    await viewModel.createContainer(spec: spec)
}
```

## ⚠️ 当前限制

1. **Docker Run 暂不支持：**
   - `--network` - 网络配置
   - `--link` - 容器链接
   - `--restart` - 重启策略
   - `--entrypoint` - 入口点覆盖
   - `--user` - 用户设置

2. **Docker Compose 暂不支持：**
   - `build` - 构建配置（仅支持已存在的镜像）
   - `healthcheck` - 健康检查
   - `deploy` - 部署配置
   - 复杂的网络配置
   - secrets 和 configs

3. **Apple Container 固有限制：**
   - 某些 Docker 特性在 macOS container 中可能不可用
   - 端口映射依赖于 Apple Container 的网络实现

## 🔮 未来增强

### Phase 2 计划
- [ ] 完整的 YAML 解析器（使用 Yams 库）
- [ ] 支持更多 Docker Run 参数
- [ ] 依赖顺序启动（respects `depends_on`）
- [ ] 环境变量和卷的完整支持
- [ ] 导出为 docker-compose.yml

### Phase 3 计划
- [ ] Docker Compose 项目管理（启动/停止整个栈）
- [ ] 日志聚合（查看整个项目的日志）
- [ ] 网络隔离和服务发现
- [ ] 健康检查和自动重启
- [ ] 资源限制和监控

## 💡 实现建议

### 添加完整的 YAML 解析

推荐使用 [Yams](https://github.com/jpsim/Yams) 库：

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
]

// DockerComposeParser.swift
import Yams

static func parse(yamlContent: String) throws -> ComposeApp {
    let yaml = try Yams.load(yaml: yamlContent) as? [String: Any]
    // 解析 services, volumes, networks
}
```

### 项目管理

创建 `ComposeProject` 来管理整个应用栈：

```swift
struct ComposeProject {
    let name: String
    let containers: [String] // Container IDs
    let volumes: [String]
    let networks: [String]
    
    func start() async throws { /* 按依赖顺序启动 */ }
    func stop() async throws { /* 停止所有容器 */ }
    func logs() async -> AsyncStream<String> { /* 聚合日志 */ }
}
```

## 📖 相关资源

- [Docker Run 文档](https://docs.docker.com/engine/reference/commandline/run/)
- [Docker Compose 文档](https://docs.docker.com/compose/compose-file/)
- [Apple Container CLI 文档](https://developer.apple.com/documentation/containerization)
