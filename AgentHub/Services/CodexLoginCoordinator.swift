import Foundation

struct CodexDeviceAuthChallenge: Equatable {
    var verificationURL: URL
    var userCode: String
    var expiresInMinutes: Int?
}

enum CodexLoginCoordinatorError: LocalizedError {
    case loginInProgress
    case loginNotStarted
    case challengeUnavailable(String)
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case .loginInProgress:
            return "Codex login is already in progress"
        case .loginNotStarted:
            return "Codex login has not been started"
        case let .challengeUnavailable(message):
            return message
        case let .loginFailed(message):
            return message
        }
    }
}

final class CodexLoginCoordinator {
    private let authService: CodexAuthService
    private let paths: AppPaths
    private let bundle: Bundle
    private let fileManager: FileManager

    private let stateLock = NSLock()
    private var currentProcess: Process?
    private var completionTask: Task<CodexAuthState, Error>?

    init(
        authService: CodexAuthService,
        paths: AppPaths,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.authService = authService
        self.paths = paths
        self.bundle = bundle
        self.fileManager = fileManager
    }

    func startLogin() async throws -> CodexDeviceAuthChallenge {
        let codexURL = try locateCodexBinary()
        try paths.prepare(fileManager: fileManager)

        let process = Process()
        process.executableURL = codexURL
        process.arguments = ["login", "--device-auth"]
        process.currentDirectoryURL = paths.root

        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = paths.root.path
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stateLock.lock()
        if currentProcess != nil {
            stateLock.unlock()
            throw CodexLoginCoordinatorError.loginInProgress
        }
        currentProcess = process
        stateLock.unlock()

        let parserLock = NSLock()
        var parser = ChallengeParser()
        var diagnostics: [String] = []

        func appendDiagnostic(_ line: String) {
            parserLock.lock()
            diagnostics.append(line)
            parserLock.unlock()
        }

        let challengeTask = Task<CodexDeviceAuthChallenge, Error> {
            try await withCheckedThrowingContinuation { continuation in
                let continuationLock = NSLock()
                var didResolve = false

                func resolve(_ result: Result<CodexDeviceAuthChallenge, Error>) {
                    continuationLock.lock()
                    defer { continuationLock.unlock() }
                    guard !didResolve else { return }
                    didResolve = true
                    continuation.resume(with: result)
                }

                let handleLine: (String) -> Void = { line in
                    let cleaned = Self.stripANSI(from: line).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleaned.isEmpty else { return }

                    parserLock.lock()
                    let challenge = parser.consume(line: cleaned)
                    parserLock.unlock()

                    if let challenge {
                        resolve(.success(challenge))
                    } else {
                        appendDiagnostic(cleaned)
                    }
                }

                Self.installReadabilityHandler(on: stdoutPipe.fileHandleForReading, handleLine: handleLine)
                Self.installReadabilityHandler(on: stderrPipe.fileHandleForReading, handleLine: handleLine)

                process.terminationHandler = { process in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    let stdoutTail = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stderrTail = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    for line in (stdoutTail + "\n" + stderrTail).split(separator: "\n", omittingEmptySubsequences: true) {
                        handleLine(String(line))
                    }

                    if process.terminationStatus != 0 {
                        parserLock.lock()
                        let message = diagnostics.joined(separator: "\n")
                        parserLock.unlock()
                        resolve(.failure(CodexLoginCoordinatorError.challengeUnavailable(
                            message.isEmpty ? "Codex login did not provide a browser challenge" : message
                        )))
                    }
                }

                do {
                    try process.run()
                } catch {
                    resolve(.failure(CodexRuntimeError.launchFailed(String(describing: error))))
                }
            }
        }

        stateLock.lock()
        completionTask = Task {
            let exitCode = await Self.waitForExit(of: process)
            defer { self.clearCurrentProcess() }

            if exitCode != 0 {
                parserLock.lock()
                let message = diagnostics.joined(separator: "\n")
                parserLock.unlock()
                throw CodexLoginCoordinatorError.loginFailed(
                    message.isEmpty ? "Codex login failed" : message
                )
            }

            return try self.authService.refreshStatus()
        }
        stateLock.unlock()

        return try await challengeTask.value
    }

    func waitForCompletion() async throws -> CodexAuthState {
        stateLock.lock()
        let task = completionTask
        stateLock.unlock()

        guard let task else {
            throw CodexLoginCoordinatorError.loginNotStarted
        }

        defer {
            stateLock.lock()
            if completionTask == task {
                completionTask = nil
            }
            stateLock.unlock()
        }

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

    static func parseChallenge(from lines: [String]) -> CodexDeviceAuthChallenge? {
        var parser = ChallengeParser()
        for line in lines {
            if let challenge = parser.consume(line: stripANSI(from: line)) {
                return challenge
            }
        }
        return nil
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

    private static func installReadabilityHandler(on handle: FileHandle, handleLine: @escaping (String) -> Void) {
        var buffer = Data()
        handle.readabilityHandler = { readableHandle in
            let chunk = readableHandle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)

            while let range = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)
                let line = String(data: lineData, encoding: .utf8) ?? ""
                handleLine(line)
            }
        }
    }

    private static func waitForExit(of process: Process) async -> Int32 {
        await withCheckedContinuation { continuation in
            let existingHandler = process.terminationHandler
            process.terminationHandler = { terminatedProcess in
                existingHandler?(terminatedProcess)
                continuation.resume(returning: terminatedProcess.terminationStatus)
            }
        }
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

private struct ChallengeParser {
    var verificationURL: URL?
    var userCode: String?
    var expiresInMinutes: Int?

    mutating func consume(line: String) -> CodexDeviceAuthChallenge? {
        if verificationURL == nil {
            verificationURL = Self.extractURL(from: line)
        }
        if userCode == nil {
            userCode = Self.extractCode(from: line)
        }
        if expiresInMinutes == nil {
            expiresInMinutes = Self.extractExpiryMinutes(from: line)
        }

        if let verificationURL, let userCode {
            return CodexDeviceAuthChallenge(
                verificationURL: verificationURL,
                userCode: userCode,
                expiresInMinutes: expiresInMinutes
            )
        }
        return nil
    }

    private static func extractURL(from line: String) -> URL? {
        guard let match = line.range(of: #"https://\S+"#, options: .regularExpression) else {
            return nil
        }
        return URL(string: String(line[match]))
    }

    private static func extractCode(from line: String) -> String? {
        guard let match = line.range(of: #"[A-Z0-9]{4,}-[A-Z0-9]{4,}"#, options: .regularExpression) else {
            return nil
        }
        return String(line[match])
    }

    private static func extractExpiryMinutes(from line: String) -> Int? {
        guard let match = line.range(of: #"expires in \d+ minutes"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let phrase = String(line[match])
        guard let digits = phrase.range(of: #"\d+"#, options: .regularExpression) else {
            return nil
        }
        return Int(phrase[digits])
    }
}
