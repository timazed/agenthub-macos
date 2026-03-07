import Foundation

enum CodexLoginCoordinatorError: LocalizedError {
    case loginInProgress
    case loginNotStarted
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case .loginInProgress:
            return "Codex login is already in progress"
        case .loginNotStarted:
            return "Codex login has not been started"
        case let .loginFailed(message):
            return message
        }
    }
}

private final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(contentsOf text: String) {
        let newLines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !newLines.isEmpty else { return }

        lock.lock()
        lines.append(contentsOf: newLines)
        lock.unlock()
    }

    func snapshot() -> String {
        lock.lock()
        let value = lines.joined(separator: "\n")
        lock.unlock()
        return value
    }
}

final class CodexLoginCoordinator {
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

    func startLogin() async throws -> AuthLoginChallenge? {
        let codexURL = try locateCodexBinary()
        try paths.prepare(fileManager: fileManager)
        let process = Process()
        process.executableURL = codexURL
        process.arguments = ["login"]
        process.currentDirectoryURL = paths.root

        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = paths.root.path
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try reserve(process: process)

        let diagnostics = LockedLines()
        let completionTask = Task<AuthState, Error> {
            defer { self.clearCurrentProcess() }

            do {
                try process.run()
            } catch {
                throw CodexRuntimeError.launchFailed(String(describing: error))
            }

            process.waitUntilExit()

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            diagnostics.append(contentsOf: Self.stripANSI(from: stdout))
            diagnostics.append(contentsOf: Self.stripANSI(from: stderr))

            guard process.terminationStatus == 0 else {
                let message = diagnostics.snapshot()
                throw CodexLoginCoordinatorError.loginFailed(
                    message.isEmpty ? "Codex login failed" : message
                )
            }

            return try self.statusRefresher()
        }

        storeCompletionTask(completionTask)
        return nil
    }

    func waitForCompletion() async throws -> AuthState {
        guard let task = snapshotCompletionTask() else {
            throw CodexLoginCoordinatorError.loginNotStarted
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

    private func reserve(process: Process) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard currentProcess == nil else {
            throw CodexLoginCoordinatorError.loginInProgress
        }
        currentProcess = process
    }

    private func storeCompletionTask(_ task: Task<AuthState, Error>) {
        stateLock.lock()
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

    private func locateCodexBinary() throws -> URL {
        if let resourcesURL = bundle.resourceURL {
            let candidates = [
                resourcesURL.appendingPathComponent("codex", isDirectory: false),
                resourcesURL.appendingPathComponent("codex/codex", isDirectory: false),
            ]

            for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        let workspaceCandidate = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("AgentHub/Resources/codex/codex", isDirectory: false)
        if fileManager.isExecutableFile(atPath: workspaceCandidate.path) {
            return workspaceCandidate
        }

        throw CodexRuntimeError.binaryNotFound
    }

    private static func stripANSI(from text: String) -> String {
        let pattern = #"\u001B\[[0-9;?]*[ -/]*[@-~]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}
