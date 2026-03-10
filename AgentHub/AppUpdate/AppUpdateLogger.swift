import Foundation

protocol AppUpdateLogging {
    func log(_ message: String)
}

final class AppUpdateLogger: AppUpdateLogging {
    private let paths: AppPaths
    private let fileManager: FileManager
    private let activityLogStore: ActivityLogStore?
    private let timestampProvider: () -> Date
    private let lock = NSLock()

    init(
        paths: AppPaths,
        fileManager: FileManager = .default,
        activityLogStore: ActivityLogStore? = nil,
        timestampProvider: @escaping () -> Date = Date.init
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.activityLogStore = activityLogStore
        self.timestampProvider = timestampProvider
    }

    func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        do {
            try paths.prepare(fileManager: fileManager)
            let timestamp = ISO8601DateFormatter().string(from: timestampProvider())
            let line = "[\(timestamp)] [AgentHub][AppUpdate] \(message)\n"
            let logURL = paths.logsDirectory.appendingPathComponent("app-update.log")
            let data = Data(line.utf8)

            if !fileManager.fileExists(atPath: logURL.path) {
                try data.write(to: logURL, options: [.atomic])
            } else {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            }

            if let activityLogStore {
                try? activityLogStore.append(
                    ActivityEvent(
                        id: UUID(),
                        taskId: nil,
                        kind: .assistantAction,
                        message: "[AppUpdate] \(message)",
                        createdAt: timestampProvider()
                    )
                )
            }
        } catch {
            let line = "[AgentHub][AppUpdate] log_failed error=\(error.localizedDescription) message=\(message)"
            print(line)
        }
    }
}
