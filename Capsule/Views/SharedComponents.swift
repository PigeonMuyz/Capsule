import SwiftUI

// MARK: - Shared UI Components

/// Section wrapper for consistent styling
struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

/// Row for displaying key-value pairs
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.body)
                .foregroundColor(.primary)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// Status badge for containers
struct StatusBadge: View {
    let status: ContainerStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(status.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .cornerRadius(12)
    }

    private var statusColor: Color {
        switch status {
        case .running: return .green
        case .starting: return .orange
        case .stopped, .created: return .gray
        case .failed: return .red
        default: return .secondary
        }
    }
}
