import SwiftUI

@main
struct CapsuleApp: App {
    @StateObject private var viewModel = ContainerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Container...") {
                    // Trigger new container sheet
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: ContainerViewModel
    @State private var selectedTab = "containers"

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedTab) {
                Section("Docker") {
                    NavigationLink(value: "containers") {
                        Label("Containers", systemImage: "cube.fill")
                    }

                    NavigationLink(value: "images") {
                        Label("Images", systemImage: "photo.stack.fill")
                    }

                    NavigationLink(value: "volumes") {
                        Label("Volumes", systemImage: "externaldrive.fill")
                    }

                    NavigationLink(value: "networks") {
                        Label("Networks", systemImage: "network")
                    }
                }

                Section("General") {
                    NavigationLink(value: "settings") {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            // Main content
            switch selectedTab {
            case "containers":
                ContainersListView(viewModel: viewModel)
            case "images":
                ImagesPlaceholderView()
            case "volumes":
                VolumesPlaceholderView()
            case "networks":
                NetworksPlaceholderView()
            case "settings":
                SettingsPlaceholderView()
            default:
                Text("Select a section")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Capsule")
    }
}

// MARK: - Placeholder Views

struct ImagesPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Images")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Image management coming soon")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VolumesPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Volumes")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Volume management coming soon")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NetworksPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Networks")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Network management coming soon")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Settings coming soon")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView(viewModel: ContainerViewModel())
        .frame(width: 1000, height: 700)
}
