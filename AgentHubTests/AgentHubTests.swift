//
//  AgentHubTests.swift
//  AgentHubTests
//
//  Created by Timothy Zelinsky on 4/3/2026.
//

import Foundation
import Testing
@testable import AgentHub

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
    @MainActor
    func computeNextRunSupportsManualAndInterval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let orchestrator = TaskOrchestrator(
            taskStore: try TaskStore(paths: paths),
            taskRunStore: TaskRunStore(paths: paths),
            activityLogStore: ActivityLogStore(paths: paths),
            personaManager: PersonaManager(paths: paths),
            workspaceManager: WorkspaceManager(),
            paths: paths,
            runtimeConfigStore: AppRuntimeConfigStore(paths: paths),
            runtimeFactory: { DummyRuntime() }
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manual = orchestrator.computeNextRun(after: now, scheduleType: TaskScheduleType.manual, scheduleValue: "")
        let interval = orchestrator.computeNextRun(after: now, scheduleType: TaskScheduleType.intervalMinutes, scheduleValue: "30")

        #expect(manual == nil)
        #expect(interval != nil)
        #expect(abs(interval!.timeIntervalSince(now) - 1800) < 1)
    }

    @Test
    func browserRetryProbeIndicatesInteractivePageResponse() throws {
        let probe = ChromiumRetryProbe(
            url: "https://www.opentable.com/sake-house",
            title: "Sake House By Hikari - OpenTable",
            readyState: "complete",
            visibleResultCount: 2,
            hasDialog: false
        )

        #expect(probe.indicatesPageResponse)
    }

    @Test
    func restaurantSearchRequestDefaultsMatchPrototypeInputs() throws {
        let request = ChromiumRestaurantSearchRequest.opentableDefault

        #expect(request.siteURL == "https://www.opentable.com")
        #expect(request.query == "Sake House By Hikari Culver City")
        #expect(request.venueName == "Sake House By Hikari")
        #expect(request.locationHint == "Culver City")
    }

    @Test
    func openTableBookingIntentParsesVenueAndLocation() throws {
        let intent = ChatBrowserIntent.parse("make a reservation for me on opentable. Sake House By Hikari. culver city. march 8. 7pm. 2 people.")

        #expect(intent != nil)
        #expect(intent?.bookingRequested == true)
        #expect(intent?.request.siteURL == "https://www.opentable.com")
        #expect(intent?.request.venueName == "Sake House By Hikari")
        #expect(intent?.request.locationHint == "culver city")
        #expect(intent?.request.query == "Sake House By Hikari culver city")
    }

    @Test
    func openTableNavigationIntentParsesVenueAndLocation() throws {
        let intent = ChatBrowserIntent.parse("navigate to the Sake House By Hikari. culver city. page on open table")

        #expect(intent != nil)
        #expect(intent?.bookingRequested == false)
        #expect(intent?.request.venueName == "Sake House By Hikari")
        #expect(intent?.request.locationHint == "culver city")
    }

}

private struct DummyRuntime: CodexRuntime {
    func startNewThread(prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        CodexExecutionResult(threadId: "dummy", exitCode: 0, stdout: "", stderr: "")
    }

    func resumeThread(threadId: String, prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        CodexExecutionResult(threadId: threadId, exitCode: 0, stdout: "", stderr: "")
    }

    func streamEvents() -> AsyncStream<CodexEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRun() throws {}
}
