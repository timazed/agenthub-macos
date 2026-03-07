import Foundation

final class ScheduleRunner {
    private let taskStore: TaskStore
    private let orchestrator: TaskOrchestrator
    private let paths: AppPaths
    private let fileManager: FileManager
    private let inAppScheduler = InAppTaskScheduler()
    private let launchAgentsDirectory: URL
    private let labelPrefix: String

    init(
        taskStore: TaskStore,
        orchestrator: TaskOrchestrator,
        paths: AppPaths,
        fileManager: FileManager = .default,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "au.com.roseadvisory.AgentHub"
    ) {
        self.taskStore = taskStore
        self.orchestrator = orchestrator
        self.paths = paths
        self.fileManager = fileManager
        self.launchAgentsDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
        self.labelPrefix = "\(bundleIdentifier).task"
    }

    func reconcileAll(appExecutableURL: URL) throws {
        let startedAt = Date()
        let tasks = try taskStore.load()
        try log("reconcile_start task_count=\(tasks.count)")
        for task in tasks {
            try sync(task: task, appExecutableURL: appExecutableURL)
        }
        try log("reconcile_finish duration_ms=\(durationMillis(since: startedAt)) task_count=\(tasks.count)")
    }

    func reconcileAllAsync(appExecutableURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try self.reconcileAll(appExecutableURL: appExecutableURL)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func sync(task: TaskRecord, appExecutableURL: URL) throws {
        if !isAutoRunnable(task) {
            inAppScheduler.unschedule(taskId: task.id)
            try unloadLaunchAgent(taskId: task.id)
            return
        }

        let config = TaskScheduleConfiguration(scheduleType: task.scheduleType, scheduleValue: task.scheduleValue)
        if !config.runsEveryDay {
            try? unloadLaunchAgent(taskId: task.id)
            inAppScheduler.schedule(task: task) { [weak self] taskId in
                Task {
                    _ = try? await self?.orchestrator.runTask(taskId: taskId)
                }
            }
            try log("sync_task_finish task_id=\(task.id.uuidString) mode=inapp")
            return
        }

        do {
            try log("sync_task_start task_id=\(task.id.uuidString) schedule=\(task.scheduleType.rawValue):\(task.scheduleValue)")
            try installLaunchAgent(task: task, appExecutableURL: appExecutableURL)
            inAppScheduler.unschedule(taskId: task.id)
            try log("sync_task_finish task_id=\(task.id.uuidString) mode=launchagent")
        } catch {
            inAppScheduler.schedule(task: task) { [weak self] taskId in
                Task {
                    _ = try? await self?.orchestrator.runTask(taskId: taskId)
                }
            }
            try log("sync_task_fallback task_id=\(task.id.uuidString) reason=\(error.localizedDescription)")
        }
    }

    func runTask(taskId: UUID) async -> Int32 {
        do {
            _ = try await orchestrator.runTask(taskId: taskId)
            return 0
        } catch {
            try? appendScheduledLog("Task \(taskId) failed: \(error.localizedDescription)")
            return 1
        }
    }

    private func isAutoRunnable(_ task: TaskRecord) -> Bool {
        if task.scheduleType == .manual {
            return false
        }
        return task.state == .scheduled
    }

    private func installLaunchAgent(task: TaskRecord, appExecutableURL: URL) throws {
        let startedAt = Date()
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        let plistURL = launchAgentPlistURL(taskId: task.id)
        let plist = try launchAgentPlist(task: task, appExecutableURL: appExecutableURL)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: [.atomic])
        try persistMirror(plist: plist, taskId: task.id)

        let domain = "gui/\(getuid())"
        try? runLaunchctl(["bootout", "\(domain)/\(launchAgentLabel(taskId: task.id))"])
        try runLaunchctl(["bootstrap", domain, plistURL.path])
        try runLaunchctl(["enable", "\(domain)/\(launchAgentLabel(taskId: task.id))"])
        try log("install_launch_agent task_id=\(task.id.uuidString) duration_ms=\(durationMillis(since: startedAt))")
    }

    private func unloadLaunchAgent(taskId: UUID) throws {
        let startedAt = Date()
        let label = launchAgentLabel(taskId: taskId)
        let domain = "gui/\(getuid())"
        try? runLaunchctl(["bootout", "\(domain)/\(label)"])

        let plistURL = launchAgentPlistURL(taskId: taskId)
        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }

        let mirrorURL = paths.launchAgentsMirrorDirectory.appendingPathComponent("\(taskId.uuidString).json")
        if fileManager.fileExists(atPath: mirrorURL.path) {
            try fileManager.removeItem(at: mirrorURL)
        }
        try log("unload_launch_agent task_id=\(taskId.uuidString) duration_ms=\(durationMillis(since: startedAt))")
    }

    private func launchAgentPlist(task: TaskRecord, appExecutableURL: URL) throws -> [String: Any] {
        let config = TaskScheduleConfiguration(scheduleType: task.scheduleType, scheduleValue: task.scheduleValue)
        var plist: [String: Any] = [
            "Label": launchAgentLabel(taskId: task.id),
            "ProgramArguments": [appExecutableURL.path, "--run-task", task.id.uuidString],
            "RunAtLoad": false,
            "StandardOutPath": paths.logsDirectory.appendingPathComponent("task-\(task.id)-stdout.log").path,
            "StandardErrorPath": paths.logsDirectory.appendingPathComponent("task-\(task.id)-stderr.log").path
        ]

        switch task.scheduleType {
        case .manual:
            break
        case .intervalMinutes:
            let minutes = max(1, config.intervalMinutes ?? 1)
            plist["StartInterval"] = minutes * 60
        case .dailyAtHHMM:
            guard let dailyTime = config.dailyTime else {
                throw NSError(domain: "ScheduleRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid daily HH:mm schedule"])
            }
            plist["StartCalendarInterval"] = ["Hour": dailyTime.hour, "Minute": dailyTime.minute]
        }

        return plist
    }

    private func persistMirror(plist: [String: Any], taskId: UUID) throws {
        try paths.prepare(fileManager: fileManager)
        let url = paths.launchAgentsMirrorDirectory.appendingPathComponent("\(taskId.uuidString).json")
        let data = try JSONSerialization.data(withJSONObject: plist, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
    }

    private func runLaunchctl(_ arguments: [String]) throws {
        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "launchctl failed"
            try? log("launchctl_failed duration_ms=\(durationMillis(since: startedAt)) args=\(arguments.joined(separator: " ")) error=\(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            throw NSError(domain: "ScheduleRunner", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output])
        }

        try? log("launchctl_ok duration_ms=\(durationMillis(since: startedAt)) args=\(arguments.joined(separator: " "))")
    }

    private func launchAgentLabel(taskId: UUID) -> String {
        "\(labelPrefix).\(taskId.uuidString)"
    }

    private func launchAgentPlistURL(taskId: UUID) -> URL {
        launchAgentsDirectory.appendingPathComponent("\(launchAgentLabel(taskId: taskId)).plist")
    }

    private func appendScheduledLog(_ line: String) throws {
        try paths.prepare(fileManager: fileManager)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("[\(timestamp)] \(line)\n".utf8)

        if !fileManager.fileExists(atPath: paths.scheduledLogURL.path) {
            try data.write(to: paths.scheduledLogURL, options: [.atomic])
            return
        }

        let handle = try FileHandle(forWritingTo: paths.scheduledLogURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }

    private func log(_ message: String) throws {
        let line = "[AgentHub][ScheduleRunner] \(message)"
        print(line)
        try appendScheduledLog(line)
    }

    private func durationMillis(since startedAt: Date) -> Int {
        Int(Date().timeIntervalSince(startedAt) * 1000)
    }
}

private final class InAppTaskScheduler {
    private var timers: [UUID: DispatchSourceTimer] = [:]
    private let queue = DispatchQueue(label: "au.com.roseadvisory.agenthub.task-scheduler")

    func schedule(task: TaskRecord, onFire: @escaping (UUID) -> Void) {
        unschedule(taskId: task.id)
        guard task.state == .scheduled else { return }
        let config = TaskScheduleConfiguration(scheduleType: task.scheduleType, scheduleValue: task.scheduleValue)

        let timer = DispatchSource.makeTimerSource(queue: queue)
        switch task.scheduleType {
        case .manual:
            return
        case .intervalMinutes:
            let minutes = max(1, config.intervalMinutes ?? 1)
            let seconds = TimeInterval(minutes * 60)
            let initialDelay = max(config.nextRun(after: Date())?.timeIntervalSinceNow ?? seconds, 1)
            timer.schedule(deadline: .now() + initialDelay, repeating: seconds)
        case .dailyAtHHMM:
            guard let delay = nextDelay(scheduleType: task.scheduleType, scheduleValue: task.scheduleValue) else { return }
            timer.schedule(deadline: .now() + delay, repeating: 24 * 60 * 60)
        }

        timer.setEventHandler { [taskID = task.id, config] in
            guard config.includes(Date()) else { return }
            onFire(taskID)
        }

        timers[task.id] = timer
        timer.resume()
    }

    func unschedule(taskId: UUID) {
        if let timer = timers.removeValue(forKey: taskId) {
            timer.cancel()
        }
    }

    private func nextDelay(scheduleType: TaskScheduleType, scheduleValue: String) -> TimeInterval? {
        let config = TaskScheduleConfiguration(scheduleType: scheduleType, scheduleValue: scheduleValue)
        guard let nextRun = config.nextRun(after: Date()) else {
            return nil
        }
        return nextRun.timeIntervalSinceNow
    }
}
