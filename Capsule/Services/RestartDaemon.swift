import Foundation
import OSLog
import Combine

private let logger = Logger(subsystem: "io.github.pigeonmuyz.capsule", category: "restart-daemon")

/// Background daemon that monitors container status and implements software-based restart policies.
/// Polls containers at fixed intervals and restarts them according to their configured policy.
@MainActor
final class RestartDaemon: ObservableObject {
    let objectWillChange = PassthroughSubject<Void, Never>()

    private let runtime: RuntimeCore
    private let policyStore = RestartPolicyStore.shared
    private var task: Task<Void, Never>?
    private let pollInterval: TimeInterval = 5.0

    /// Track consecutive failures per container to implement backoff
    private var failureCounts: [String: Int] = [:]

    init(runtime: RuntimeCore) {
        self.runtime = runtime
    }

    /// Start the daemon (call once at app launch)
    func start() {
        guard task == nil else { return }
        logger.info("RestartDaemon starting")

        task = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    /// Stop the daemon
    func stop() {
        task?.cancel()
        task = nil
        logger.info("RestartDaemon stopped")
    }

    private func tick() async {
        do {
            let containers = try await runtime.listContainers()

            for container in containers {
                let policy = policyStore.policy(for: container.id)
                guard policy != .no else { continue }

                // Skip if manually stopped by user
                if policyStore.isManuallyStopped(container.id) {
                    continue
                }

                // Evaluate restart condition
                let shouldRestart = evaluateRestartCondition(container: container, policy: policy)

                if shouldRestart {
                    await attemptRestart(container: container, policy: policy)
                }
            }
        } catch {
            logger.error("RestartDaemon tick failed: \(error)")
        }
    }

    private func evaluateRestartCondition(container: ContainerSummary, policy: RestartPolicy) -> Bool {
        switch policy {
        case .no:
            return false

        case .always:
            // Restart if stopped for any reason
            return container.status == .stopped || container.status == .failed

        case .unlessStopped:
            // Restart unless user manually stopped it
            // (already filtered above by isManuallyStopped check)
            return container.status == .stopped || container.status == .failed

        case .onFailure:
            // Only restart if exited with non-zero code
            if container.status == .failed {
                return true
            }
            // If stopped with exitCode != 0
            if container.status == .stopped, let exitCode = container.exitCode, exitCode != 0 {
                return true
            }
            return false
        }
    }

    private func attemptRestart(container: ContainerSummary, policy: RestartPolicy) async {
        let failures = failureCounts[container.id] ?? 0

        // Exponential backoff: wait 2^failures seconds (max 60s)
        let backoffDelay = min(pow(2.0, Double(failures)), 60.0)

        // Skip if we just restarted recently (basic rate limiting)
        if failures > 0 {
            logger.info("Container \(container.name) (\(container.id)) backoff: \(backoffDelay)s before retry \(failures + 1)")
            try? await Task.sleep(for: .seconds(backoffDelay))
        }

        do {
            logger.info("Restarting container \(container.name) (\(container.id)) per policy \(policy.rawValue)")
            try await runtime.startContainer(id: container.id)

            // Success — reset failure count
            failureCounts[container.id] = 0
            logger.info("Container \(container.name) restarted successfully")

        } catch {
            failureCounts[container.id] = failures + 1
            logger.error("Failed to restart container \(container.name): \(error)")

            // Give up after 5 consecutive failures
            if failureCounts[container.id]! >= 5 {
                logger.error("Container \(container.name) failed 5 times, giving up")
                // Optionally: remove the policy or mark as permanently failed
            }
        }
    }
}
