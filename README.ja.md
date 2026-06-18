# Capsule

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | 日本語

Capsule は、Apple containers を集中したデスクトップ UI から管理するためのネイティブ macOS アプリです。

システムの `container` ランタイムを SwiftUI の使いやすい体験として包み込みます。コンテナ、イメージ、ボリューム、ネットワーク、Linux machines、ログ、ファイル、統計情報、シェル入口、Docker 風のインポートを、ひとつのコンパクトなウィンドウで扱えます。

## Why Capsule

Apple のコンテナツールは強力ですが、日常作業では視覚的な操作面が欲しくなります。実行中のコンテナを確認する、負荷の高いコンテナを止める、ログを開く、イメージを pull する、慣れた `docker run` コマンドを Apple container ランタイム向けの設定へ変換する、といった操作です。

Capsule は、そのワークフローのための軽量なネイティブシェルです。名前の意味もそのままです。各コンテナは capsule のようなもので、macOS から離れずに検査、起動、停止、オープン、削除できます。

## Features

- コンテナ管理：一覧表示、作成、起動、停止、削除、詳細表示、更新。
- ランタイム詳細：状態、イメージ、CPU、メモリ、稼働時間、ログ、統計情報、ファイルブラウザ、ターミナル入口。
- イメージ管理：ローカルイメージの一覧表示、pull、詳細表示、削除。
- 専用のネイティブ画面でボリュームとネットワークを管理。
- Apple container tooling による Linux machines の管理。
- Docker ワークフローのインポート：
  - `docker run` コマンドの解析。
  - Docker Compose サービスの解析。
  - Compose プロジェクトの起動、停止、削除、依存順序、グループ化されたログ。
- ランタイム動作と外部ターミナル設定のためのネイティブ macOS Settings。
- `Localizable.xcstrings` によるローカライズ済み UI 文字列。

## Requirements

- macOS 26.0 以降。
- ソースからビルドする場合は Xcode 26 以降。
- Apple container tooling がインストールされ、`/usr/local/bin/container` から利用できること。
- 現在の Apple container スタックでは Apple Silicon Mac を推奨します。

Capsule は現時点では Container CLI のインストール、ブートストラップ、初期化を行いません。先に Apple container tooling を自分でインストールし、初期化してください。

- [apple/container](https://github.com/apple/container)

Capsule を起動する前に、Terminal で container ランタイムが動作することを確認してください。

```bash
/usr/local/bin/container system status
/usr/local/bin/container list --all
```

システムが起動していない場合は、次のコマンドで起動できます。

```bash
/usr/local/bin/container system start
```

Capsule 側で、アプリと連動して container system を起動・停止する設定もできます。

## Build

プロジェクトを clone して Xcode で開きます。

```bash
git clone https://github.com/PigeonMuyz/Capsule.git
cd Capsule
open Capsule.xcodeproj
```

その後、`Capsule` scheme を選び、`My Mac` で実行してください。

Xcode は Apple の `containerization` package を含む Swift Package 依存関係を自動的に解決します。

## Project Structure

```text
Capsule/
├── Capsule/
│   ├── Models/          # コンテナとログのモデル
│   ├── Runtime/         # RuntimeCore と container CLI ブリッジ
│   ├── Services/        # Docker / Compose の解析とプロジェクトロジック
│   ├── ViewModels/      # 監視可能なアプリ状態
│   ├── Views/           # SwiftUI 画面と詳細パネル
│   ├── ContentView.swift
│   └── Localizable.xcstrings
├── Capsule.xcodeproj
└── README.md
```

## Tech Stack

- Swift と SwiftUI。
- actors と async/await を使った Swift Concurrency。
- Apple Containerization Swift packages。
- Apple `container` CLI integration。
- OSLog によるランタイム診断。

## Notes

Capsule は Apple container エコシステム向けの実験的なネイティブクライアントです。アプリはインストール済みの `container` コマンドの挙動と JSON 出力に従うため、Apple のツールが進化するにつれて一部の画面に調整が必要になる場合があります。

## License

Capsule is released under the MIT License. See [LICENSE](LICENSE).
