import Foundation

enum ClaudeLoginCoordinatorError: LocalizedError {
    case loginInProgress
    case loginNotStarted
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case .loginInProgress:
            return "Claude login is already in progress"
        case .loginNotStarted:
            return "Claude login has not been started"
        case let .loginFailed(message):
            return message
        }
    }
}

final class ClaudeLoginCoordinator {
    private let statusRefresher: () throws -> AuthState
    private let paths: AppPaths
    private let bundle: Bundle
    private let fileManager: FileManager

    private let stateLock = NSLock()
    private var currentProcess: Process?
    private var completionTask: Task<AuthState, Error>?

    init(
        statusRefresher: @escaping () throws -> AuthState,
        paths: AppPaths,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.statusRefresher = statusRefresher
        self.paths = paths
        self.bundle = bundle
        self.fileManager = fileManager
    }

    func startLogin() async throws {
        let claudeURL = try locateClaudeBinary()
        try fileManager.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try reserve()

        let process = Process()
        process.executableURL = claudeURL
        process.arguments = ["auth", "login"]
        process.currentDirectoryURL = paths.root
        process.environment = ClaudeRuntime.buildEnvironment(claudeHome: paths.root.path)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let completionTask = Task<AuthState, Error> {
            defer { self.clearCurrentProcess() }

            do {
                try process.run()
            } catch {
                throw AssistantRuntimeError.launchFailed(String(describing: error))
            }

            process.waitUntilExit()

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let combined = [stdout, stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            guard process.terminationStatus == 0 else {
                throw ClaudeLoginCoordinatorError.loginFailed(
                    combined.isEmpty ? "Claude login failed" : combined
                )
            }

            return try self.statusRefresher()
        }

        store(process: process, task: completionTask)
    }

    func waitForCompletion() async throws -> AuthState {
        guard let task = snapshotCompletionTask() else {
            throw ClaudeLoginCoordinatorError.loginNotStarted
        }

        defer { clearCompletionTask(ifMatching: task) }
        return try await task.value
    }

    func cancel() {
        stateLock.lock()
        let process = currentProcess
        currentProcess = nil
        completionTask = nil
        stateLock.unlock()
        process?.terminate()
    }

    private func reserve() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard currentProcess == nil else {
            throw ClaudeLoginCoordinatorError.loginInProgress
        }
    }

    private func store(process: Process, task: Task<AuthState, Error>) {
        stateLock.lock()
        currentProcess = process
        completionTask = task
        stateLock.unlock()
    }

    private func snapshotCompletionTask() -> Task<AuthState, Error>? {
        stateLock.lock()
        let task = completionTask
        stateLock.unlock()
        return task
    }

    private func clearCompletionTask(ifMatching task: Task<AuthState, Error>) {
        stateLock.lock()
        if completionTask == task {
            completionTask = nil
        }
        stateLock.unlock()
    }

    private func clearCurrentProcess() {
        stateLock.lock()
        currentProcess = nil
        stateLock.unlock()
    }

    private func locateClaudeBinary() throws -> URL {
        if let resourcesURL = bundle.resourceURL {
            let candidates = [
                resourcesURL.appendingPathComponent("claude", isDirectory: false),
                resourcesURL.appendingPathComponent("claude/claude", isDirectory: false),
            ]

            for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        let workspaceCandidate = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("AgentHub/Resources/claude/claude", isDirectory: false)
        if fileManager.isExecutableFile(atPath: workspaceCandidate.path) {
            return workspaceCandidate
        }

        throw AssistantRuntimeError.launchFailed("Bundled claude binary not found")
    }
}
