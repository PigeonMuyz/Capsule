# Capsule

[English](README.md) | [简体中文](README.zh-CN.md) | 繁體中文 | [日本語](README.ja.md)

Capsule 是一款原生 macOS 應用程式，用來透過專注的桌面介面管理 Apple containers。

它把系統 `container` 執行環境包裝成乾淨的 SwiftUI 體驗：容器、映像檔、卷宗、網路、Linux machines、日誌、檔案、統計資訊、Shell 入口和 Docker 風格匯入，都集中在一個精簡的視窗裡。

## 為什麼是 Capsule

Apple 的容器工具很強大，但日常工作常常需要一個視覺化介面：查看正在執行的容器、停止佔用資源的容器、開啟日誌、拉取映像檔，或把熟悉的 `docker run` 命令轉換成 Apple container 執行環境可使用的設定。

Capsule 就是這套工作流程上的輕量原生外殼。名稱也很直接：每個容器都像一個 capsule，你可以檢查、啟動、停止、開啟或移除它，而不需要離開 macOS。

## 功能

- 管理容器：列表、建立、啟動、停止、刪除、查看詳情和重新整理。
- 查看執行環境資訊：狀態、映像檔、CPU、記憶體、執行時間、日誌、統計資訊、檔案瀏覽器和終端機入口。
- 管理映像檔：列出、拉取、查看和刪除本機映像檔。
- 在獨立的原生介面中管理卷宗和網路。
- 管理由 Apple container 工具支援的 Linux machines。
- 匯入 Docker 工作流程：
  - 解析 `docker run` 命令。
  - 解析 Docker Compose 服務。
  - Compose 專案的啟動、停止、刪除、相依順序和分組日誌。
- 原生 macOS 設定，用於執行環境行為和外部終端機偏好。
- 透過 `Localizable.xcstrings` 提供在地化 UI 字串。

## 系統需求

- macOS 26.0 或更新版本。
- 從原始碼建置需要 Xcode 26 或更新版本。
- 已安裝 Apple container 工具，並可透過 `/usr/local/bin/container` 存取。
- 目前 Apple container 技術棧建議使用 Apple Silicon Mac。

Capsule 暫時不提供 Container CLI 的安裝、引導或初始化能力。請先自行安裝並初始化 Apple container 工具：

- [apple/container](https://github.com/apple/container)

啟動 Capsule 前，請先在終端機確認 container 執行環境可用：

```bash
/usr/local/bin/container system status
/usr/local/bin/container list --all
```

如果系統尚未執行，可以使用：

```bash
/usr/local/bin/container system start
```

Capsule 也可以設定為隨應用程式啟動和停止 container system。

## 建置

複製專案並用 Xcode 開啟：

```bash
git clone https://github.com/PigeonMuyz/Capsule.git
cd Capsule
open Capsule.xcodeproj
```

接著選擇 `Capsule` scheme，並在 `My Mac` 上執行。

Xcode 會自動解析 Swift Package 依賴，包括 Apple 的 `containerization` package。

## 專案結構

```text
Capsule/
├── Capsule/
│   ├── Models/          # 容器和日誌模型
│   ├── Runtime/         # RuntimeCore 與 container CLI 橋接
│   ├── Services/        # Docker / Compose 解析和專案邏輯
│   ├── ViewModels/      # 可觀察的應用狀態
│   ├── Views/           # SwiftUI 畫面和詳情面板
│   ├── ContentView.swift
│   └── Localizable.xcstrings
├── Capsule.xcodeproj
└── README.md
```

## 技術棧

- Swift 和 SwiftUI。
- Swift Concurrency，包含 actors 和 async/await。
- Apple Containerization Swift packages。
- Apple `container` CLI 整合。
- OSLog 執行環境診斷。

## 說明

Capsule 是 Apple container 生態的實驗性原生客戶端。應用程式會跟隨已安裝的 `container` 命令行為和 JSON 輸出，因此當 Apple 工具鏈演進時，部分畫面可能需要同步調整。

## 授權

Capsule 使用 MIT License 發布。詳見 [LICENSE](LICENSE)。
