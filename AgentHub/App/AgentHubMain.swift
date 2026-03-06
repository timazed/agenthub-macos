import Foundation
import SwiftUI

@main
enum AgentHubMain {
    static func main() {
        let args = CommandLine.arguments
        appendStartupLog("argv=\(args.joined(separator: " "))")

        if let taskId = parseTaskId(args: args) {
            appendStartupLog("entry=headless task_id=\(taskId.uuidString)")
            let semaphore = DispatchSemaphore(value: 0)
            var exitCode: Int32 = 1

            Task {
                exitCode = await HeadlessTaskCommand().run(taskId: taskId)
                semaphore.signal()
            }

            semaphore.wait()
            Foundation.exit(exitCode)
        }

        appendStartupLog("entry=gui")
        AgentHubApp.main()
    }

    private static func parseTaskId(args: [String]) -> UUID? {
        guard let index = args.firstIndex(of: "--run-task"), args.indices.contains(index + 1) else {
            return nil
        }
        return UUID(uuidString: args[index + 1])
    }

    private static func appendStartupLog(_ line: String) {
        let fileManager = FileManager.default
        let logsDirectory = AppPaths.defaultRoot().appendingPathComponent("logs", isDirectory: true)
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let logURL = logsDirectory.appendingPathComponent("startup.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let payload = Data("[\(timestamp)] [AgentHub][Main] \(line)\n".utf8)

        if !fileManager.fileExists(atPath: logURL.path) {
            try? payload.write(to: logURL, options: [.atomic])
            return
        }

        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: payload)
        try? handle.close()
    }
}

struct HeadlessTaskCommand {
    func run(taskId: UUID) async -> Int32 {
        do {
            let container = try AppContainer.makeHeadless()
            return await container.scheduleRunner.runTask(taskId: taskId)
        } catch {
            fputs("Headless task failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}
