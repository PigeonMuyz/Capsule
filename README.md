# Capsule

English | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md)

Capsule is a native macOS app for managing Apple containers from a focused desktop interface.

It wraps the system `container` runtime in a clean SwiftUI experience: containers, images, volumes, networks, Linux machines, logs, files, stats, shell access, and Docker-style imports all live in one compact window.

## Why Capsule

Apple's container tooling is powerful, but day-to-day work often needs a visual surface: see what is running, stop a noisy container, open logs, pull an image, or turn a familiar `docker run` command into something the Apple container runtime can use.

Capsule is that small native shell around the workflow. The name is literal: each container is a capsule you can inspect, start, stop, open, and remove without leaving macOS.

## Features

- Manage containers: list, create, start, stop, delete, inspect, and refresh.
- View runtime details: status, image, CPU, memory, uptime, logs, stats, file browser, and terminal entry points.
- Manage images: list, pull, inspect, and remove local images.
- Manage volumes and networks from dedicated native views.
- Manage Linux machines backed by Apple container tooling.
- Import Docker workflows:
  - `docker run` command parsing.
  - Docker Compose service parsing.
  - Compose project start, stop, remove, dependency ordering, and grouped logs.
- Native macOS settings for runtime behavior and external terminal preferences.
- Localized UI strings through `Localizable.xcstrings`.

## Requirements

- macOS 26.0 or later.
- Xcode 26 or later for building from source.
- Apple container tooling installed and available at `/usr/local/bin/container`.
- Apple Silicon Mac is recommended for the current Apple container stack.

Capsule does not install, bootstrap, or initialize the Container CLI yet. Install and initialize Apple's container tooling yourself first:

- [apple/container](https://github.com/apple/container)

Before launching Capsule, make sure the container runtime works in Terminal:

```bash
/usr/local/bin/container system status
/usr/local/bin/container list --all
```

If the system is not running, start it with:

```bash
/usr/local/bin/container system start
```

Capsule can also be configured to start and stop the container system with the app.

## Build

Clone the project and open it in Xcode:

```bash
git clone https://github.com/PigeonMuyz/Capsule.git
cd Capsule
open Capsule.xcodeproj
```

Then choose the `Capsule` scheme and run it on `My Mac`.

Xcode will resolve the Swift Package dependencies automatically, including Apple's `containerization` package.

## Project Structure

```text
Capsule/
├── Capsule/
│   ├── Models/          # Container and log models
│   ├── Runtime/         # RuntimeCore and container CLI bridge
│   ├── Services/        # Docker and Compose parsing/project logic
│   ├── ViewModels/      # Observable app state
│   ├── Views/           # SwiftUI screens and detail panels
│   ├── ContentView.swift
│   └── Localizable.xcstrings
├── Capsule.xcodeproj
└── README.md
```

## Tech Stack

- Swift and SwiftUI.
- Swift Concurrency with actors and async/await.
- Apple Containerization Swift packages.
- Apple `container` CLI integration.
- OSLog for runtime diagnostics.

## Notes

Capsule is an experimental native client for Apple's container ecosystem. The app follows the behavior and JSON output of the installed `container` command, so some screens may need small adjustments as Apple's tooling evolves.

## License

Capsule is released under the MIT License. See [LICENSE](LICENSE).
