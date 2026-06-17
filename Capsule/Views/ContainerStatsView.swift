import SwiftUI

/// Container statistics view showing resource usage
struct ContainerStatsView: View {
    let containerID: String
    let containerName: String

    @State private var cpuUsage: Double = 0
    @State private var memoryUsage: UInt64 = 0
    @State private var memoryLimit: UInt64 = 0
    @State private var networkRx: UInt64 = 0
    @State private var networkTx: UInt64 = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // CPU Usage
                statsCard(
                    title: "CPU Usage",
                    icon: "cpu",
                    color: .blue
                ) {
                    ProgressView(value: cpuUsage, total: 100)
                        .progressViewStyle(.linear)

                    Text("\(String(format: "%.1f", cpuUsage))%")
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                // Memory Usage
                statsCard(
                    title: "Memory",
                    icon: "memorychip",
                    color: .purple
                ) {
                    ProgressView(value: Double(memoryUsage), total: Double(memoryLimit))
                        .progressViewStyle(.linear)

                    HStack {
                        Text(formatBytes(memoryUsage))
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("/ \(formatBytes(memoryLimit))")
                            .foregroundStyle(.secondary)
                    }
                }

                // Network I/O
                statsCard(
                    title: "Network",
                    icon: "network",
                    color: .green
                ) {
                    HStack(spacing: 40) {
                        VStack(alignment: .leading) {
                            Label("RX", systemImage: "arrow.down.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatBytes(networkRx))
                                .font(.title3)
                                .fontWeight(.semibold)
                        }

                        VStack(alignment: .leading) {
                            Label("TX", systemImage: "arrow.up.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatBytes(networkTx))
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                    }
                }

                Text("Statistics are simulated. Real-time monitoring coming soon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top)
            }
            .padding()
        }
        .onAppear {
            startMonitoring()
        }
    }

    private func statsCard<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
            }

            content()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    private func startMonitoring() {
        // Simulate stats (replace with real monitoring)
        cpuUsage = Double.random(in: 5...30)
        memoryUsage = UInt64.random(in: 100_000_000...500_000_000)
        memoryLimit = 1024 * 1024 * 1024
        networkRx = UInt64.random(in: 1_000_000...100_000_000)
        networkTx = UInt64.random(in: 500_000...50_000_000)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

#Preview {
    ContainerStatsView(containerID: "test", containerName: "test-container")
        .frame(width: 600, height: 400)
}
