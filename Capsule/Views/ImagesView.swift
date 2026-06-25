import SwiftUI

/// Middle column of the Images view: the image list. Auto-refreshes on a timer.
struct ImagesListColumn: View {
    @ObservedObject var viewModel: ContainerViewModel
    @Binding var selection: ContainerCLI.ImageInfo?

    @State private var images: [ContainerCLI.ImageInfo] = []
    @State private var showingPullSheet = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && images.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if images.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(images) { image in
                            ImageRow(
                                image: image,
                                isSelected: selection?.id == image.id,
                                onSelect: { selection = image },
                                onDelete: { deleteImage(image) }
                            )
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationTitle("Images")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingPullSheet = true }) {
                    Label("Pull", systemImage: "plus")
                }
                .help("Pull Image")
            }
        }
        .sheet(isPresented: $showingPullSheet) {
            PullImageView { reference in
                Task {
                    do {
                        try await viewModel.runtime.pullImage(reference: reference)
                        await loadImages()
                    } catch {
                        errorMessage = "Failed to pull image: \(error.localizedDescription)"
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await loadImages()
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
    }

    private var refreshInterval: Double {
        let i = UserDefaults.standard.double(forKey: "autoRefreshInterval")
        return max(i > 0 ? i : 2.0, 5)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Images")
                .font(.title3)
                .fontWeight(.semibold)

            Button(action: { showingPullSheet = true }) {
                Label("Pull Image", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadImages() async {
        isLoading = true
        do {
            images = try await viewModel.runtime.listImages()
        } catch {
            errorMessage = "Failed to load images: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func deleteImage(_ image: ContainerCLI.ImageInfo) {
        Task {
            do {
                try await viewModel.runtime.deleteImage(id: image.id)
                if selection?.id == image.id { selection = nil }
                await loadImages()
            } catch {
                errorMessage = "Failed to delete image: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Image Row

struct ImageRow: View {
    let image: ContainerCLI.ImageInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: "photo")
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(image.repository)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(image.tag)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(formatSize(image.size))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Image Detail Panel (Picker-style tabs)

struct ImageDetailPanel: View {
    let image: ContainerCLI.ImageInfo?
    @ObservedObject var viewModel: ContainerViewModel

    @State private var selectedTab: DetailTab = .overview

    enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case layers = "Layers"
        case history = "History"

        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let image = image {
                switch selectedTab {
                case .overview:
                    ImageOverviewView(image: image, viewModel: viewModel)
                case .layers:
                    ImageLayersView(image: image)
                case .history:
                    ImageHistoryView(image: image)
                }
            } else {
                NoSelectionView(icon: "photo.stack", message: "Select an image to view details")
            }
        }
        .navigationTitle(image?.repository ?? "Image")
        .navigationSubtitle(image?.tag ?? "")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .disabled(image == nil)
            }
        }
    }
}

// MARK: - Overview View

struct ImageOverviewView: View {
    let image: ContainerCLI.ImageInfo
    @ObservedObject var viewModel: ContainerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Actions
                InfoSection(title: "Actions") {
                    HStack(spacing: 12) {
                        Button(action: createContainer) {
                            Label("Create Container", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: tagImage) {
                            Label("Tag", systemImage: "tag")
                        }
                        .buttonStyle(.bordered)

                        Button(action: pushImage) {
                            Label("Push", systemImage: "arrow.up.circle")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(role: .destructive, action: deleteImage) {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // General
                InfoSection(title: "General") {
                    InfoRow(label: "Repository", value: image.repository)
                    Divider()
                    InfoRow(label: "Tag", value: image.tag)
                    Divider()
                    InfoRow(label: "ID", value: String(image.id.prefix(12)))
                    Divider()
                    InfoRow(label: "Size", value: formatSize(image.size))
                }

                // Details
                InfoSection(title: "Details") {
                    InfoRow(label: "Digest", value: String(image.digest.suffix(12)))
                    if !image.created.isEmpty {
                        Divider()
                        InfoRow(label: "Created", value: image.created)
                    }
                }

                Spacer(minLength: 16)
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func createContainer() {
        Task {
            let containerName = "container-\(UUID().uuidString.prefix(8))"
            let spec = ContainerSpec(
                name: containerName,
                image: image.configuration.name,
                cpus: 2,
                memoryBytes: 2 * 1024 * 1024 * 1024,
                command: []
            )
            await viewModel.createContainer(spec: spec)
        }
    }

    private func tagImage() {
        // TODO: Implement tag image dialog
    }

    private func pushImage() {
        // TODO: Implement push image
    }

    private func deleteImage() {
        Task {
            try? await viewModel.runtime.deleteImage(id: image.id)
        }
    }
}

// MARK: - Layers View

struct ImageLayersView: View {
    let image: ContainerCLI.ImageInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Image Layers")
                    .font(.headline)

                Text("Coming soon: View image layer information from container image inspect")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - History View

struct ImageHistoryView: View {
    let image: ContainerCLI.ImageInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Build History")
                    .font(.headline)

                Text("Coming soon: View image build history and layer commands")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Pull Image View

struct PullImageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var imageReference = ""
    @State private var isPulling = false

    let onPull: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Image") {
                    HStack {
                        TextField("Image Reference", text: $imageReference, prompt: Text("nginx:latest"))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        if let sourceTag {
                            Text(sourceTag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.16))
                                .clipShape(Capsule())
                        }
                    }
                }

                if isPulling {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Pulling image...")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Pull Image")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isPulling)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Pull") { pullImage() }
                        .disabled(imageReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPulling)
                }
            }
            .frame(width: 520, height: 240)
        }
    }

    private var sourceTag: String? {
        let reference = imageReference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if reference.hasPrefix("ghcr.io/") { return "GitHub" }
        if reference.hasPrefix("docker.io/") || !reference.contains("/") || reference.hasPrefix("library/") {
            return "Docker Hub"
        }
        return nil
    }

    private func pullImage() {
        isPulling = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            onPull(imageReference)
            dismiss()
        }
    }
}
