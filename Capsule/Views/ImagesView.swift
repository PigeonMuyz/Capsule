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

    @StateObject private var iconCache = ImageIconCache.shared

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 镜像图标（从 Docker Hub 获取或使用占位符）
                Group {
                    if let icon = iconCache.getIcon(for: image.repository) {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 32, height: 32)
                .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(displayName):\(image.tag)")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(formatSize(image.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 来源标签居中显示在最右侧
                if let badge = registryBadge {
                    Text(badge)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.15))
                        .foregroundStyle(badgeColor)
                        .cornerRadius(4)
                }
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

    // 简化显示名称：使用共享的辅助函数
    private var displayName: String {
        ImageDisplayHelper.simplifyRepository(image.repository)
    }

    // 根据 registry 显示对应的标签
    private var registryBadge: String? {
        ImageDisplayHelper.getRegistryBadge(image.repository)
    }

    // 标签颜色
    private var badgeColor: Color {
        ImageDisplayHelper.getBadgeColor(image.repository)
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

        var title: LocalizedStringKey {
            switch self {
            case .overview: return "Overview"
            case .layers: return "Layers"
            case .history: return "History"
            }
        }
    }

    var body: some View {
        Group {
            if let image = image {
                switch selectedTab {
                case .overview:
                    ImageOverviewView(image: image, viewModel: viewModel)
                case .layers:
                    ImageLayersView(image: image, viewModel: viewModel)
                case .history:
                    ImageHistoryView(image: image, viewModel: viewModel)
                }
            } else {
                NoSelectionView(icon: "photo.stack", message: "Select an image to view details")
            }
        }
        .navigationTitle(displayName)
        .navigationSubtitle(image?.tag ?? "")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .disabled(image == nil)
            }
        }
    }

    private var displayName: String {
        guard let repo = image?.repository else { return "Image" }
        return ImageDisplayHelper.simplifyRepository(repo)
    }
}

// MARK: - Overview View

struct ImageOverviewView: View {
    let image: ContainerCLI.ImageInfo
    @ObservedObject var viewModel: ContainerViewModel
    @State private var showingTagSheet = false
    @State private var showingPushConfirmation = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

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
                        .disabled(isWorking)

                        Button(action: pushImage) {
                            Label("Push", systemImage: "arrow.up.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isWorking)

                        Spacer()

                        if isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Button(role: .destructive, action: deleteImage) {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isWorking)
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
        .sheet(isPresented: $showingTagSheet) {
            TagImageView(sourceReference: image.configuration.name) { target in
                Task { await performTag(target: target) }
            }
        }
        .confirmationDialog(
            "Push Image",
            isPresented: $showingPushConfirmation,
            titleVisibility: .visible
        ) {
            Button("Push") {
                Task { await performPush() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(image.configuration.name)
        }
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
        showingTagSheet = true
    }

    private func pushImage() {
        showingPushConfirmation = true
    }

    private func deleteImage() {
        Task {
            await performDelete()
        }
    }

    private func performTag(target: String) async {
        isWorking = true
        errorMessage = nil
        do {
            try await viewModel.runtime.tagImage(source: image.configuration.name, target: target)
        } catch {
            errorMessage = String.localizedStringWithFormat(
                NSLocalizedString("Failed to tag image: %@", comment: "Image tag error"),
                error.localizedDescription
            )
        }
        isWorking = false
    }

    private func performPush() async {
        isWorking = true
        errorMessage = nil
        do {
            try await viewModel.runtime.pushImage(reference: image.configuration.name)
        } catch {
            errorMessage = String.localizedStringWithFormat(
                NSLocalizedString("Failed to push image: %@", comment: "Image push error"),
                error.localizedDescription
            )
        }
        isWorking = false
    }

    private func performDelete() async {
        isWorking = true
        errorMessage = nil
        do {
            try await viewModel.runtime.deleteImage(id: image.id)
        } catch {
            errorMessage = String.localizedStringWithFormat(
                NSLocalizedString("Failed to delete image: %@", comment: "Image delete error"),
                error.localizedDescription
            )
        }
        isWorking = false
    }
}

// MARK: - Layers View

struct ImageLayersView: View {
    let image: ContainerCLI.ImageInfo
    @ObservedObject var viewModel: ContainerViewModel
    @State private var report: ImageInspectReport?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                layerContent
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: image.id) {
            await loadInspect()
        }
    }

    @ViewBuilder
    private var layerContent: some View {
        if isLoading {
            InfoSection(title: "Image Layers") {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
            }
        } else if let errorMessage {
            InfoSection(title: "Image Layers") {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } else if let report, !report.variants.isEmpty {
            ForEach(report.variants) { variant in
                InfoSection(title: "Image Layers") {
                    ImageVariantHeaderView(variant: variant)
                    Divider()

                    if variant.layers.isEmpty {
                        Text("No image layers found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(variant.layers) { layer in
                            ImageLayerRowView(layer: layer)
                            if layer.id != variant.layers.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        } else {
            InfoSection(title: "Image Layers") {
                Text("No image layers found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadInspect() async {
        isLoading = true
        errorMessage = nil
        do {
            let inspectText = try await viewModel.runtime.inspectImage(reference: image.configuration.name)
            report = try ImageInspectReport.parse(inspectText)
        } catch {
            report = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - History View

struct ImageHistoryView: View {
    let image: ContainerCLI.ImageInfo
    @ObservedObject var viewModel: ContainerViewModel
    @State private var report: ImageInspectReport?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InfoSection(title: "Build History") {
                    InfoRow(label: "Reference", value: image.configuration.name)
                    Divider()
                    InfoRow(label: "ID", value: image.id)
                    Divider()
                    InfoRow(label: "Digest", value: image.digest)
                    if !image.created.isEmpty {
                        Divider()
                        InfoRow(label: "Created", value: image.created)
                    }
                }

                historyContent
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: image.id) {
            await loadInspect()
        }
    }

    private func loadInspect() async {
        isLoading = true
        errorMessage = nil
        do {
            let inspectText = try await viewModel.runtime.inspectImage(reference: image.configuration.name)
            report = try ImageInspectReport.parse(inspectText)
        } catch {
            report = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @ViewBuilder
    private var historyContent: some View {
        if isLoading {
            InfoSection(title: "History") {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
            }
        } else if let errorMessage {
            InfoSection(title: "History") {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } else if let report, !report.variants.isEmpty {
            ForEach(report.variants) { variant in
                InfoSection(title: "History") {
                    ImageVariantHeaderView(variant: variant)
                    Divider()

                    if variant.history.isEmpty {
                        Text("No build history found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(variant.history) { entry in
                            ImageHistoryRowView(entry: entry)
                            if entry.id != variant.history.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        } else {
            InfoSection(title: "History") {
                Text("No build history found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ImageVariantHeaderView: View {
    let variant: ImageInspectReport.VariantSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoRow(label: "Platform", value: variant.platform)
            Divider()
            InfoRow(label: "Digest", value: variant.digest)
            if let size = variant.size {
                Divider()
                InfoRow(label: "Size", value: formatSize(size))
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct ImageLayerRowView: View {
    let layer: ImageInspectReport.LayerSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("#\(layer.index)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(layer.digest)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if let command = layer.command, !command.isEmpty {
                    Text(command)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct ImageHistoryRowView: View {
    let entry: ImageInspectReport.HistorySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(entry.index)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)

                Text(entry.command.isEmpty ? String(localized: "Image metadata") : entry.command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                Spacer()

                if entry.emptyLayer {
                    Text("Empty layer")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }

            HStack(spacing: 10) {
                if !entry.created.isEmpty {
                    Label(entry.created, systemImage: "clock")
                }
                if !entry.comment.isEmpty {
                    Label(entry.comment, systemImage: "text.bubble")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 46)
        }
        .padding(.vertical, 8)
    }
}

private struct ImageInspectReport {
    let variants: [VariantSummary]

    struct VariantSummary: Identifiable {
        let id: String
        let digest: String
        let platform: String
        let size: Int64?
        let layers: [LayerSummary]
        let history: [HistorySummary]
    }

    struct LayerSummary: Identifiable {
        let id: String
        let index: Int
        let digest: String
        let command: String?
    }

    struct HistorySummary: Identifiable {
        let id: String
        let index: Int
        let created: String
        let command: String
        let comment: String
        let emptyLayer: Bool
    }

    static func parse(_ raw: String) throws -> ImageInspectReport {
        guard let data = raw.data(using: .utf8) else {
            throw ImageInspectError.invalidData
        }

        let records = try JSONDecoder().decode([ImageInspectRecord].self, from: data)
        let variants = records.flatMap { record -> [VariantSummary] in
            (record.variants ?? []).enumerated().map { variantIndex, variant in
                let variantID = variant.digest ?? "\(variantIndex)"
                let history = (variant.config?.history ?? []).enumerated().map { index, entry in
                    HistorySummary(
                        id: "\(variantID)-history-\(index)",
                        index: index + 1,
                        created: entry.created ?? "",
                        command: entry.createdBy ?? "",
                        comment: entry.comment ?? "",
                        emptyLayer: entry.emptyLayer ?? false
                    )
                }
                let nonEmptyHistory = history.filter { !$0.emptyLayer }
                let layers = (variant.config?.rootfs?.diffIDs ?? []).enumerated().map { index, digest in
                    LayerSummary(
                        id: "\(variantID)-layer-\(index)",
                        index: index + 1,
                        digest: digest,
                        command: index < nonEmptyHistory.count ? nonEmptyHistory[index].command : nil
                    )
                }

                return VariantSummary(
                    id: variantID,
                    digest: variant.digest ?? record.configuration?.descriptor?.digest ?? record.id ?? "",
                    platform: platformDisplay(variant: variant),
                    size: variant.size,
                    layers: layers,
                    history: history
                )
            }
        }

        return ImageInspectReport(variants: variants)
    }

    private static func platformDisplay(variant: ImageInspectRecord.Variant) -> String {
        let platform = variant.platform
        let config = variant.config
        let os = platform?.os ?? config?.os
        let architecture = platform?.architecture ?? config?.architecture
        let variantName = platform?.variant ?? config?.variant
        return [os, architecture, variantName]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "/")
    }

    enum ImageInspectError: LocalizedError {
        case invalidData

        var errorDescription: String? {
            switch self {
            case .invalidData:
                return String(localized: "Unable to parse image inspect output")
            }
        }
    }
}

private struct ImageInspectRecord: Decodable {
    let id: String?
    let configuration: Configuration?
    let variants: [Variant]?

    struct Configuration: Decodable {
        let descriptor: Descriptor?

        struct Descriptor: Decodable {
            let digest: String?
        }
    }

    struct Variant: Decodable {
        let digest: String?
        let size: Int64?
        let platform: Platform?
        let config: Config?

        struct Platform: Decodable {
            let architecture: String?
            let os: String?
            let variant: String?
        }

        struct Config: Decodable {
            let architecture: String?
            let os: String?
            let variant: String?
            let rootfs: RootFS?
            let history: [HistoryEntry]?

            struct RootFS: Decodable {
                let diffIDs: [String]?

                enum CodingKeys: String, CodingKey {
                    case diffIDs = "diff_ids"
                }
            }

            struct HistoryEntry: Decodable {
                let created: String?
                let createdBy: String?
                let comment: String?
                let emptyLayer: Bool?

                enum CodingKeys: String, CodingKey {
                    case created
                    case createdBy = "created_by"
                    case comment
                    case emptyLayer = "empty_layer"
                }
            }
        }
    }
}

private struct TagImageView: View {
    @Environment(\.dismiss) private var dismiss
    let sourceReference: String
    let onTag: (String) -> Void

    @State private var targetReference = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Text(sourceReference)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                Section("Target") {
                    TextField("Image Reference", text: $targetReference, prompt: Text("registry.example.com/app:tag"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Tag Image")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Tag") {
                        onTag(targetReference.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(targetReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(width: 520, height: 280)
        }
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
        if reference.hasPrefix("ghcr.io/") { return String(localized: "GitHub") }
        if reference.hasPrefix("docker.io/") || !reference.contains("/") || reference.hasPrefix("library/") {
            return String(localized: "Docker Hub")
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
