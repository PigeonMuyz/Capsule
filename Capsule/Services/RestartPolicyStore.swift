import Foundation

final class RestartPolicyStore {
    static let shared = RestartPolicyStore()

    private let policiesKey = "restartPolicies"
    private let manuallyStoppedKey = "restartPolicies.manuallyStopped"
    private let defaults = UserDefaults.standard

    private init() {}

    func policy(for containerID: String) -> RestartPolicy {
        let raw = policies()[containerID] ?? RestartPolicy.no.rawValue
        return RestartPolicy(rawValue: raw) ?? .no
    }

    func save(_ policy: RestartPolicy, for containerID: String) {
        var values = policies()
        if policy.shouldPersist {
            values[containerID] = policy.rawValue
        } else {
            values.removeValue(forKey: containerID)
        }
        defaults.set(values, forKey: policiesKey)
    }

    func remove(containerID: String) {
        var values = policies()
        values.removeValue(forKey: containerID)
        defaults.set(values, forKey: policiesKey)

        var stopped = manuallyStopped()
        stopped.remove(containerID)
        defaults.set(Array(stopped), forKey: manuallyStoppedKey)
    }

    func markManuallyStopped(_ containerID: String, stopped: Bool) {
        var values = manuallyStopped()
        if stopped {
            values.insert(containerID)
        } else {
            values.remove(containerID)
        }
        defaults.set(Array(values), forKey: manuallyStoppedKey)
    }

    func isManuallyStopped(_ containerID: String) -> Bool {
        manuallyStopped().contains(containerID)
    }

    private func policies() -> [String: String] {
        defaults.dictionary(forKey: policiesKey) as? [String: String] ?? [:]
    }

    private func manuallyStopped() -> Set<String> {
        Set(defaults.stringArray(forKey: manuallyStoppedKey) ?? [])
    }
}
