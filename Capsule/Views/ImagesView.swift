import SwiftUI

/// Images management view
struct ImagesView: View {
    @ObservedObject var viewModel: ContainerViewModel
    @State private var images: [ImageInfo] = []
    @State private var showingPullSheet = false
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Header toolbar
            toolbar

            Divider()

            // Images list
            if isLoading {
                ProgressView("Loading images...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if images.isEmpty {
                emptyState
            } else {
                imagesList
            }
        }
        .sheet(isPresented: $showingPullSheet) {
            PullImageView(onPull: { reference in
                pullImage(reference)
            })
        }
        .onAppear {
            loadImages()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Images")
                .font(.title)
                .fontWeight(.bold)

            Spacer()

            Button(action: { loadImages() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button(action: { showingPullSheet = true }) {
                Label("Pull Image", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Images")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Pull an image to get started")
                .foregroundStyle(.secondary)

            Button(action: { showingPullSheet = true }) {
                Label("Pull Image", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Images List

    private var imagesList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(images) { image in
                    imageCard(image)
                }
            }
            .padding()
        }
    }

    private func imageCard(_ image: ImageInfo) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "photo.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text(image.repository)
                    .font(.headline)

                if let tag = image.tag {
                    Text(tag)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    Label(formatSize(image.size), systemImage: "externaldrive")
                    Label(image.id.prefix(12), systemImage: "number")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button(action: {
                    createContainerFromImage(image)
                }) {
                    Label("Create Container", systemImage: "play.circle")
                }

                Divider()

                Button(role: .destructive, action: {
                    deleteImage(image)
                }) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        }
    }

    // MARK: - Actions

    private func loadImages() {
        isLoading = true
        // Simulate loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            images = simulateImageList()
            isLoading = false
        }
    }

    private func pullImage(_ reference: String) {
        // Simulate pull
        let newImage = ImageInfo(
            id: UUID().uuidString,
            repository: reference,
            tag: "latest",
            size: Int64.random(in: 10_000_000...500_000_000),
            created: Date()
        )
        images.append(newImage)
    }

    private func deleteImage(_ image: ImageInfo) {
        images.removeAll { $0.id == image.id }
    }

    private func createContainerFromImage(_ image: ImageInfo) {
        // TODO: Open create container sheet with pre-filled image
    }

    private func simulateImageList() -> [ImageInfo] {
        return [
            ImageInfo(
                id: "sha256:abc123",
                repository: "docker.io/library/alpine",
                tag: "latest",
                size: 7_500_000,
                created: Date().addingTimeInterval(-86400 * 7)
            ),
            ImageInfo(
                id: "sha256:def456",
                repository: "docker.io/library/postgres",
                tag: "14-alpine",
                size: 245_000_000,
                created: Date().addingTimeInterval(-86400 * 3)
            ),
            ImageInfo(
                id: "sha256:ghi789",
                repository: "docker.io/library/redis",
                tag: "7-alpine",
                size: 32_000_000,
                created: Date().addingTimeInterval(-86400 * 1)
            ),
        ]
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Image Info Model

struct ImageInfo: Identifiable {
    let id: String
    let repository: String
    let tag: String?
    let size: Int64
    let created: Date
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
                Section("Image Reference") {
                    TextField("docker.io/library/alpine:latest", text: $imageReference)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Text("Examples: alpine, nginx:latest, postgres:14")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isPulling)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Pull") {
                        pullImage()
                    }
                    .disabled(imageReference.isEmpty || isPulling)
                }
            }
            .frame(width: 500, height: 250)
        }
    }

    private func pullImage() {
        isPulling = true
        // Simulate pull delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onPull(imageReference)
            dismiss()
        }
    }
}

#Preview {
    ImagesView(viewModel: ContainerViewModel())
        .frame(width: 900, height: 600)
}
