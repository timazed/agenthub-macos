import Foundation
import Testing
@testable import AgentHub

@MainActor
struct CodexLoginCoordinatorTests {
    @Test
    func waitForCompletionSucceedsOnceStatusTurnsAuthenticated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let terminatedMarkerURL = root.appendingPathComponent("terminated.txt", isDirectory: false)
        let scriptURL = try makeExecutableScript(
            in: root,
            name: "codex-login-sleep.sh",
            contents: """
            #!/bin/sh
            trap 'echo terminated > "$CODEX_HOME/terminated.txt"; exit 0' TERM
            while true; do
              sleep 1
            done
            """
        )

        let authState = LockedAuthState(
            AuthState(status: .unauthenticated, accountLabel: nil, lastValidatedAt: nil, failureReason: "Not logged in", updatedAt: Date())
        )
        let coordinator = CodexLoginCoordinator(
            statusRefresher: { authState.snapshot() },
            paths: AppPaths(root: root),
            codexBinaryLocator: CodexBinaryLocator(binaryURLProvider: { scriptURL }),
            pollIntervalNanoseconds: 50_000_000,
            timeoutNanoseconds: 2_000_000_000
        )

        _ = try await coordinator.startLogin()
        Task.detached {
            try? await Task.sleep(nanoseconds: 150_000_000)
            authState.update(
                AuthState(status: .authenticated, accountLabel: "user@example.com", lastValidatedAt: Date(), failureReason: nil, updatedAt: Date())
            )
        }

        let state = try await coordinator.waitForCompletion()
        coordinator.cancel()

        #expect(state.status == .authenticated)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(FileManager.default.fileExists(atPath: terminatedMarkerURL.path))
    }

    @Test
    func waitForCompletionSurfacesLauncherFailureWhenAuthNeverCompletes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let scriptURL = try makeExecutableScript(
            in: root,
            name: "codex-login-fail.sh",
            contents: """
            #!/bin/zsh
            echo "browser handoff failed" >&2
            exit 1
            """
        )

        let coordinator = CodexLoginCoordinator(
            statusRefresher: {
                AuthState(status: .unauthenticated, accountLabel: nil, lastValidatedAt: nil, failureReason: "Not logged in", updatedAt: Date())
            },
            paths: AppPaths(root: root),
            codexBinaryLocator: CodexBinaryLocator(binaryURLProvider: { scriptURL }),
            pollIntervalNanoseconds: 50_000_000,
            timeoutNanoseconds: 2_000_000_000
        )

        _ = try await coordinator.startLogin()

        do {
            _ = try await coordinator.waitForCompletion()
            Issue.record("Expected login failure")
        } catch let error as CodexLoginCoordinatorError {
            #expect(error.errorDescription?.contains("browser handoff failed") == true)
        }
    }

    @Test
    func waitForCompletionIgnoresTransientStatusErrorsWhileLauncherIsRunning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let scriptURL = try makeExecutableScript(
            in: root,
            name: "codex-login-running.sh",
            contents: """
            #!/bin/sh
            while true; do
              sleep 1
            done
            """
        )

        let statusProbe = LockedStatusProbe([
            .failure("status warming up"),
            .failure("status still warming up"),
            .state(AuthState(status: .unauthenticated, accountLabel: nil, lastValidatedAt: nil, failureReason: "Not logged in", updatedAt: Date())),
            .state(AuthState(status: .authenticated, accountLabel: "user@example.com", lastValidatedAt: Date(), failureReason: nil, updatedAt: Date()))
        ])
        let coordinator = CodexLoginCoordinator(
            statusRefresher: { try statusProbe.next() },
            paths: AppPaths(root: root),
            codexBinaryLocator: CodexBinaryLocator(binaryURLProvider: { scriptURL }),
            pollIntervalNanoseconds: 50_000_000,
            timeoutNanoseconds: 10_000_000_000,
            sleeper: { _ in }
        )

        _ = try await coordinator.startLogin()
        let state = try await coordinator.waitForCompletion()
        coordinator.cancel()

        #expect(state.status == .authenticated)
    }
}

private final class LockedAuthState: @unchecked Sendable {
    private let lock = NSLock()
    private var state: AuthState

    init(_ state: AuthState) {
        self.state = state
    }

    func update(_ state: AuthState) {
        lock.lock()
        self.state = state
        lock.unlock()
    }

    func snapshot() -> AuthState {
        lock.lock()
        let value = state
        lock.unlock()
        return value
    }
}

private final class LockedStatusProbe: @unchecked Sendable {
    enum Step {
        case state(AuthState)
        case failure(String)
    }

    private let lock = NSLock()
    private var steps: [Step]

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func next() throws -> AuthState {
        lock.lock()
        let step = steps.isEmpty ? Step.failure("No status steps remaining") : steps.removeFirst()
        lock.unlock()

        switch step {
        case let .state(state):
            return state
        case let .failure(message):
            throw AssistantRuntimeError.launchFailed(message)
        }
    }
}

private func makeExecutableScript(in directory: URL, name: String, contents: String) throws -> URL {
    let url = directory.appendingPathComponent(name, isDirectory: false)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}
