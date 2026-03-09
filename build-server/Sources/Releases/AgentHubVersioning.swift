import Foundation

struct AgentHubVersioning {
    func nextVersion(from currentVersion: String, for codexVersion: String) -> String {
        let components = currentVersion.split(separator: ".").compactMap { Int($0) }
        guard components.count == 3 else {
            return "\(currentVersion)+codex.\(sanitizedCodexVersion(codexVersion))"
        }

        return "\(components[0]).\(components[1]).\(components[2] + 1)"
    }

    func nextBuildNumber(from currentBuildNumber: Int) -> Int {
        currentBuildNumber + 1
    }

    private func sanitizedCodexVersion(_ version: String) -> String {
        version.replacingOccurrences(of: " ", with: "-")
    }
}
