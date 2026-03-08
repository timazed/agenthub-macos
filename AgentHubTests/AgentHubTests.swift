//
//  AgentHubTests.swift
//  AgentHubTests
//
//  Created by Timothy Zelinsky on 4/3/2026.
//

import Foundation
import Testing
@testable import AgentHub

@MainActor
struct AgentHubTests {
    @Test
    func taskStoreRoundTripsThreadBackedTasks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let store = try TaskStore(paths: paths)

        let task = TaskRecord(
            id: UUID(),
            title: "Bondi rentals",
            instructions: "Check for rentals under $900",
            scheduleType: .dailyAtHHMM,
            scheduleValue: "08:00",
            state: .scheduled,
            codexThreadId: "thread-123",
            personaId: "default",
            runtimeMode: .chatOnly,
            repoPath: nil,
            createdAt: .now,
            updatedAt: .now,
            lastRun: nil,
            nextRun: .now,
            lastError: nil
        )

        try store.upsert(task)
        let loaded = try store.load()

        #expect(loaded.count == 1)
        #expect(loaded.first?.codexThreadId == "thread-123")
        #expect(loaded.first?.title == "Bondi rentals")
    }

    @Test
    func computeNextRunSupportsManualAndInterval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let runtimeConfigStore = AppRuntimeConfigStore(paths: paths)
        let authStore = AuthStore(paths: paths)
        let authManager = AuthManager(
            store: authStore,
            providerClient: StubAuthProviderClient(
                refreshedState: AuthState(
                    provider: .codex,
                    status: .authenticated,
                    accountLabel: "user@example.com",
                    lastValidatedAt: Date(),
                    failureReason: nil,
                    updatedAt: Date()
                )
            )
        )
        let orchestrator = TaskOrchestrator(
            taskStore: try TaskStore(paths: paths),
            taskRunStore: TaskRunStore(paths: paths),
            activityLogStore: ActivityLogStore(paths: paths),
            personaManager: PersonaManager(paths: paths),
            workspaceManager: WorkspaceManager(),
            paths: paths,
            runtimeConfigStore: runtimeConfigStore,
            authManager: authManager,
            runtimeFactory: { DummyRuntime() }
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manual = orchestrator.computeNextRun(after: now, scheduleType: .manual, scheduleValue: "")
        let interval = orchestrator.computeNextRun(after: now, scheduleType: .intervalMinutes, scheduleValue: "30")

        #expect(manual == nil)
        #expect(interval != nil)
        #expect(abs(interval!.timeIntervalSince(now) - 1800) < 1)
    }
}

private struct DummyRuntime: AssistantRuntime {
    func startNewThread(prompt: String, config: AssistantLaunchConfig) async throws -> AssistantExecutionResult {
        AssistantExecutionResult(threadId: "dummy", exitCode: 0, stdout: "", stderr: "")
    }

    func resumeThread(threadId: String, prompt: String, config: AssistantLaunchConfig) async throws -> AssistantExecutionResult {
        AssistantExecutionResult(threadId: threadId, exitCode: 0, stdout: "", stderr: "")
    }

    func checkLoginStatus(codexHome: String) throws -> AssistantLoginStatusResult {
        AssistantLoginStatusResult(isAuthenticated: true, accountEmail: nil, message: nil)
    }

    func streamEvents() -> AsyncStream<AssistantEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRun() throws {}
}

@MainActor
private struct StubAuthProviderClient: AuthProviderClient {
    var refreshedState: AuthState

    func refreshStatus() throws -> AuthState {
        refreshedState
    }

    func startLogin() async throws -> AuthLoginChallenge? { nil }
    func waitForLoginCompletion() async throws -> AuthState { try refreshStatus() }
    func cancelLogin() {}
}
