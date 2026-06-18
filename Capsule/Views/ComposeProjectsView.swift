import SwiftUI

/// Detail panel for a compose project, shown in the right column of the
/// Containers view when a project group is selected. Embeddable (no sheet
/// chrome) — mirrors `ContainerDetailPanel`.
struct ProjectDetailPanel: View {
    let project: ComposeManager.ComposeProjectInfo
    @ObservedObject var composeManager: ComposeManager
    @State private var logs: [(service: String, line: String)] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("\(project.services.count) services")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Project-level actions
                if project.status == .running {
                    Button(action: { Task { try? await composeManager.stopProject(id: project.id) } }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: { Task { try? await composeManager.startProject(id: project.id) } }) {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Menu {
                    Button("Remove (Keep Volumes)", role: .destructive) {
                        Task { try? await composeManager.removeProject(id: project.id, removeVolumes: false) }
                    }
                    Button("Remove All", role: .destructive) {
                        Task { try? await composeManager.removeProject(id: project.id, removeVolumes: true) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    InfoSection(title: "Services") {
                        ForEach(project.services, id: \.self) { service in
                            HStack(spacing: 8) {
                                Image(systemName: "cube.fill")
                                    .foregroundStyle(.blue)
                                Text("\(project.name)-\(service)")
                                    .font(.system(.subheadline, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                            }
                        }
                    }

                    InfoSection(title: "Logs") {
                        if logs.isEmpty {
                            Text("No logs yet")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(logs.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("[\(logs[index].service)]")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(logs[index].line)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .task(id: project.id) {
            await streamLogs()
        }
    }

    private func streamLogs() async {
        logs = []
        do {
            let stream = try await composeManager.getProjectLogs(id: project.id)
            for await log in stream {
                logs.append(log)
                if logs.count > 100 { logs.removeFirst() }
            }
        } catch {
            print("Failed to stream logs: \(error)")
        }
    }
}
