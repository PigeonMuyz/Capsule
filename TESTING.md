# 系统容器集成测试指南

## 测试前提

确保你的系统中有运行的容器：
```bash
container list
```

应该能看到：
- postgres-bookshelf (running)
- redis-bookshelf (running)

## 测试步骤

### 1. 在 Xcode 中打开项目
```bash
open Capsule.xcodeproj
```

### 2. 编译并运行
- 选择 "My Mac" 作为目标
- 点击运行（⌘R）

### 3. 预期结果

**容器列表视图应该显示：**
- postgres-bookshelf
  - 状态：Running (绿色)
  - 镜像：docker.io/library/postgres:14-alpine
  - CPUs: 4
  - Memory: 1024 MB
  - IP: 192.168.64.3/24

- redis-bookshelf
  - 状态：Running (绿色)
  - 镜像：docker.io/library/redis:7-alpine
  - CPUs: 4
  - Memory: 1024 MB
  - IP: 192.168.64.2/24

### 4. 测试功能

#### 测试 1：查看容器详情
1. 点击任意容器的信息按钮（蓝色 ⓘ 图标）
2. 应该看到容器的详细信息
3. 切换到 "Logs" 标签页
4. 应该能看到容器的实时日志

#### 测试 2：停止容器（谨慎！）
1. 点击 postgres-bookshelf 的停止按钮（橙色停止图标）
2. 容器状态应该变为 "Stopped"
3. 在终端验证：`container list` 应该显示 postgres 状态为 stopped

#### 测试 3：启动容器
1. 点击刚才停止的容器的启动按钮（绿色播放图标）
2. 容器状态应该变回 "Running"
3. 在终端验证：`container list` 应该显示 postgres 状态为 running

#### 测试 4：创建新容器
1. 点击 "New Container" 按钮
2. 填写表单：
   - Name: test-alpine
   - Image: docker.io/library/alpine:latest
   - CPUs: 2
   - Memory: 1 GB
   - Command: /bin/sh
3. 点击 "Create"
4. 应该在列表中看到新容器

#### 测试 5：日志流式查看
1. 启动 redis-bookshelf（如果已停止）
2. 点击信息按钮查看详情
3. 切换到 Logs 标签
4. 应该能看到 Redis 的实时日志输出
5. 尝试搜索功能（如搜索 "Ready"）

## 已知问题和限制

### 当前版本的限制
1. **容器名称显示**：目前显示的是容器 ID，不是友好名称
   - 原因：`container list` JSON 输出中 ID 字段包含完整 ID
   - 需要修复：解析名称字段或从 ID 中提取名称

2. **创建时间**：显示为当前时间，不是实际创建时间
   - 原因：需要解析 `started` 字段或调用 `container inspect`

3. **删除功能**：删除系统容器需要谨慎
   - 建议：先测试自己创建的容器

4. **日志格式**：日志未区分 stdout/stderr
   - 原因：`container logs` 命令输出已混合
   - 可能需要使用 framework API 来分别获取

## 故障排查

### 问题：应用启动但看不到容器

**检查 1：验证 CLI 可用**
```bash
which container
container --version
```

**检查 2：查看控制台日志**
在 Xcode 中查看控制台输出，搜索 "runtime" 或 "error"

**检查 3：检查权限**
```bash
ls -la /usr/bin/container
```

### 问题：编译错误

**如果提示找不到 ContainerCLI：**
1. 确保 `Capsule/Runtime/ContainerCLI.swift` 文件存在
2. 在 Xcode Project Navigator 中刷新项目
3. Clean Build Folder (⇧⌘K)
4. 重新编译

**如果提示 sandbox 错误：**
1. 检查 `project.pbxproj` 中 `ENABLE_APP_SANDBOX = NO`
2. Clean 并重新编译

## 成功标准

✅ **基本功能**
- [ ] 能看到系统中的 postgres 和 redis 容器
- [ ] 容器状态正确显示（running/stopped）
- [ ] 能启动/停止容器
- [ ] 状态变更能在 UI 中实时反映

✅ **日志功能**
- [ ] 能查看容器历史日志
- [ ] 能实时流式查看新日志
- [ ] 日志搜索功能正常

✅ **容器管理**
- [ ] 能创建新容器（使用 alpine 测试）
- [ ] 能删除测试容器
- [ ] 操作错误时有友好提示

## 下一步改进

完成基本测试后，可以改进：

1. **名称解析**：修改 RuntimeCore 正确解析容器名称
2. **时间解析**：正确解析 ISO8601 时间戳
3. **错误处理**：改进用户可读的错误消息
4. **日志优化**：区分 stdout/stderr，添加颜色高亮
5. **状态同步**：优化轮询策略，减少 CPU 使用

---

**测试日期**：2026-06-17  
**版本**：集成系统容器 (commit b0866e4)
