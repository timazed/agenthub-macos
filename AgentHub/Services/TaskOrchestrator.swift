import Foundation

final class TaskOrchestrator {
    private let taskStore: TaskStore
    private let taskRunStore: TaskRunStore
    private let activityLogStore: ActivityLogStore
    private let personaManager: PersonaManager
    private let workspaceManager: WorkspaceManager
    private let paths: AppPaths
    private let runtimeConfigStore: AppRuntimeConfigStore
    private let runtimeFactory: () -> CodexRuntime
    private let runningLock = NSLock()
    private var runningTaskIDs = Set<UUID>()

    init(
        taskStore: TaskStore,
        taskRunStore: TaskRunStore,
        activityLogStore: ActivityLogStore,
        personaManager: PersonaManager,
        workspaceManager: WorkspaceManager,
        paths: AppPaths,
        runtimeConfigStore: AppRuntimeConfigStore,
        runtimeFactory: @escaping () -> CodexRuntime
    ) {
        self.taskStore = taskStore
        self.taskRunStore = taskRunStore
        self.activityLogStore = activityLogStore
        self.personaManager = personaManager
        self.workspaceManager = workspaceManager
        self.paths = paths
        self.runtimeConfigStore = runtimeConfigStore
        self.runtimeFactory = runtimeFactory
    }

    func loadTasks() throws -> [TaskRecord] {
        try taskStore.load().sorted { lhs, rhs in
            if lhs.state == rhs.state {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    @discardableResult
    func createTask(from proposal: TaskProposal) async throws -> TaskRecord {
        let now = Date()
        var task = TaskRecord(
            id: UUID(),
            title: proposal.title,
            instructions: proposal.instructions,
            scheduleType: proposal.scheduleType,
            scheduleValue: proposal.scheduleValue,
            state: .scheduled,
            codexThreadId: nil,
            personaId: "default",
            runtimeMode: proposal.runtimeMode,
            repoPath: proposal.externalDirectoryPath,
            createdAt: now,
            updatedAt: now,
            lastRun: nil,
            nextRun: computeNextRun(after: now, scheduleType: proposal.scheduleType, scheduleValue: proposal.scheduleValue),
            lastError: nil
        )

        try taskStore.upsert(task)
        try activityLogStore.append(ActivityEvent(id: UUID(), taskId: task.id, kind: .taskCreated, message: "\(task.title) created", createdAt: now))

        if proposal.runNow {
            task = try await runTask(taskId: task.id)
        }

        return task
    }

    @discardableResult
    func updateTask(_ task: TaskRecord) throws -> TaskRecord {
        let updated = try taskStore.update(taskId: task.id) { current in
            current.title = task.title
            current.instructions = task.instructions
            current.scheduleType = task.scheduleType
            current.scheduleValue = task.scheduleValue
            current.runtimeMode = task.runtimeMode
            current.repoPath = task.externalDirectoryPath
            current.nextRun = computeNextRun(after: Date(), scheduleType: task.scheduleType, scheduleValue: task.scheduleValue)
        }
        try activityLogStore.append(ActivityEvent(id: UUID(), taskId: updated.id, kind: .taskUpdated, message: "\(updated.title) updated", createdAt: Date()))
        return updated
    }

    @discardableResult
    func runTask(taskId: UUID) async throws -> TaskRecord {
        try beginRunning(taskId: taskId)
        defer { finishRunning(taskId: taskId) }

        var task = try taskStore.find(taskId: taskId)
        guard var task else {
            throw NSError(domain: "TaskOrchestrator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Task not found"])
        }

        let now = Date()
        task = try taskStore.update(taskId: task.id) { current in
            current.state = .running
            current.lastError = nil
        }
        try activityLogStore.append(ActivityEvent(id: UUID(), taskId: task.id, kind: .taskRunStarted, message: "\(task.title) started", createdAt: now))

        let persona = try personaManager.defaultPersona()
        let repoPath = try workspaceManager.validateExternalDirectory(path: task.externalDirectoryPath, for: task.runtimeMode)
        let runtimeConfig = try runtimeConfigStore.loadOrCreateDefault()
        let launchConfig = CodexLaunchConfig(
            agentHomeDirectory: persona.directoryPath,
            codexHome: paths.root.path,
            runtimeMode: task.runtimeMode,
            externalDirectory: repoPath,
            enableSearch: false,
            model: runtimeConfig.model,
            reasoningEffort: runtimeConfig.reasoningEffort
        )

        let runtime = runtimeFactory()
        let prompt: String
        let result: CodexExecutionResult
        let startedAt = Date()

        if let threadId = task.codexThreadId {
            prompt = buildRecurringPrompt(for: task)
            result = try await runtime.resumeThread(threadId: threadId, prompt: prompt, config: launchConfig)
        } else {
            prompt = buildBootstrapPrompt(for: task)
            result = try await runtime.startNewThread(prompt: prompt, config: launchConfig)
        }

        let finishedAt = Date()
        let nextState = classifyState(from: result)
        let nextRun = nextState == .scheduled
            ? computeNextRun(after: finishedAt, scheduleType: task.scheduleType, scheduleValue: task.scheduleValue)
            : nil

        let updated = try taskStore.update(taskId: task.id) { current in
            current.codexThreadId = current.codexThreadId ?? result.threadId
            current.state = nextState
            current.lastRun = finishedAt
            current.nextRun = nextRun
            current.lastError = result.exitCode == 0 ? nil : (result.stderr.isEmpty ? "Run failed with exit code \(result.exitCode)" : result.stderr)
        }

        let runRecord = TaskRunRecord(
            id: UUID(),
            taskId: task.id,
            codexThreadId: updated.codexThreadId,
            startedAt: startedAt,
            finishedAt: finishedAt,
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
        try taskRunStore.append(runRecord)

        let completionKind: ActivityKind = result.exitCode == 0 ? (nextState == .needsInput ? .taskNeedsInput : .taskRunCompleted) : .taskRunFailed
        let completionMessage = activityMessage(for: updated, result: result)
        try activityLogStore.append(ActivityEvent(id: UUID(), taskId: updated.id, kind: completionKind, message: completionMessage, createdAt: finishedAt))

        return updated
    }

    @discardableResult
    func pauseTask(taskId: UUID) throws -> TaskRecord {
        let updated = try taskStore.update(taskId: taskId) { current in
            current.state = .paused
            current.nextRun = nil
        }
        try activityLogStore.append(ActivityEvent(id: UUID(), taskId: updated.id, kind: .taskPaused, message: "\(updated.title) paused", createdAt: Date()))
        return updated
    }

    @discardableResult
    func resumeTask(taskId: UUID) throws -> TaskRecord {
        let updated = try taskStore.update(taskId: taskId) { current in
            current.state = .scheduled
            current.nextRun = computeNextRun(after: Date(), scheduleType: current.scheduleType, scheduleValue: current.scheduleValue)
            current.lastError = nil
        }
        try activityLogStore.append(ActivityEvent(id: UUID(), taskId: updated.id, kind: .taskScheduled, message: "\(updated.title) resumed", createdAt: Date()))
        return updated
    }

    @discardableResult
    func completeTask(taskId: UUID) throws -> TaskRecord {
        let updated = try taskStore.update(taskId: taskId) { current in
            current.state = .completed
            current.nextRun = nil
        }
        try activityLogStore.append(ActivityEvent(id: UUID(), taskId: updated.id, kind: .taskCompleted, message: "\(updated.title) completed", createdAt: Date()))
        return updated
    }

    @discardableResult
    func reinitializeThread(taskId: UUID) throws -> TaskRecord {
        let updated = try taskStore.update(taskId: taskId) { current in
            current.codexThreadId = nil
            current.state = .scheduled
            current.lastError = nil
            current.nextRun = computeNextRun(after: Date(), scheduleType: current.scheduleType, scheduleValue: current.scheduleValue)
        }
        try activityLogStore.append(ActivityEvent(id: UUID(), taskId: updated.id, kind: .taskUpdated, message: "\(updated.title) thread reinitialized", createdAt: Date()))
        return updated
    }

    func computeNextRun(after now: Date, scheduleType: TaskScheduleType, scheduleValue: String) -> Date? {
        switch scheduleType {
        case .manual:
            return nil
        case .intervalMinutes:
            let minutes = max(1, Int(scheduleValue) ?? 1)
            return Calendar.current.date(byAdding: .minute, value: minutes, to: now)
        case .dailyAtHHMM:
            let parts = scheduleValue.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1]),
                  (0...23).contains(hour),
                  (0...59).contains(minute) else {
                return nil
            }

            var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard var candidate = Calendar.current.date(from: components) else {
                return nil
            }

            if candidate <= now {
                candidate = Calendar.current.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }

            return candidate
        }
    }

    private func classifyState(from result: CodexExecutionResult) -> TaskState {
        if result.exitCode != 0 {
            return .error
        }

        let combined = "\(result.stdout)\n\(result.stderr)".lowercased()
        if combined.contains("needs_input:") || combined.contains("needs input:") {
            return .needsInput
        }
        if combined.contains("task_complete:") || combined.contains("task complete:") {
            return .completed
        }
        return .scheduled
    }

    private func activityMessage(for task: TaskRecord, result: CodexExecutionResult) -> String {
        if task.state == .needsInput {
            return "\(task.title) needs input"
        }
        if result.exitCode != 0 {
            return "\(task.title) failed"
        }
        return "\(task.title) completed a run"
    }

    private func beginRunning(taskId: UUID) throws {
        runningLock.lock()
        defer { runningLock.unlock() }
        guard !runningTaskIDs.contains(taskId) else {
            throw NSError(domain: "TaskOrchestrator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Task is already running"])
        }
        runningTaskIDs.insert(taskId)
    }

    private func finishRunning(taskId: UUID) {
        runningLock.lock()
        runningTaskIDs.remove(taskId)
        runningLock.unlock()
    }

    private func buildBootstrapPrompt(for task: TaskRecord) -> String {
        let attachedDirectoryBlock: String
        if let path = task.externalDirectoryPath, !path.isEmpty {
            attachedDirectoryBlock = """

            ATTACHED EXTERNAL DIRECTORY:
            \(path)
            Use this only when needed. Your home context remains your agent home directory.
            """
        } else {
            attachedDirectoryBlock = ""
        }

        return """
        TASK TITLE:
        \(task.title)

        TASK INSTRUCTIONS:
        \(task.instructions)\(attachedDirectoryBlock)

        EXECUTION MODE:
        This is a persistent background task. Future runs will resume this thread.
        Keep continuity across runs. Track prior findings and avoid repeating unchanged results.

        CURRENT RUN PURPOSE:
        Initialize this task and perform the first run now.

        OUTPUT:
        Provide a concise user-facing update suitable for the AgentHub activity feed.
        If you need user clarification, say so explicitly with the prefix NEEDS_INPUT:
        If the task is fully complete and should not run again, say so with the prefix TASK_COMPLETE:
        """
    }

    private func buildRecurringPrompt(for task: TaskRecord) -> String {
        let attachedDirectoryBlock: String
        if let path = task.externalDirectoryPath, !path.isEmpty {
            attachedDirectoryBlock = """

            ATTACHED EXTERNAL DIRECTORY:
            \(path)
            Use this only when needed. Your home context remains your agent home directory.
            """
        } else {
            attachedDirectoryBlock = ""
        }

        return """
        Continue the existing background task.

        CURRENT RUN PURPOSE:
        Execute the scheduled run now.

        TASK TITLE:
        \(task.title)

        TASK INSTRUCTIONS:
        \(task.instructions)\(attachedDirectoryBlock)

        OUTPUT:
        Provide:
        1. summary of what changed since last run
        2. any actions required from the user
        3. if blocked, state exactly what input is needed with the prefix NEEDS_INPUT:
        4. if the task is done permanently, say so with the prefix TASK_COMPLETE:
        """
    }
}
