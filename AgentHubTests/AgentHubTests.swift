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
    @MainActor
    @Test
    func browserAutomationServiceExecutesNavigationActions() async throws {
        let profile = BrowserProfile()
        let service = BrowserAutomationService()
        let session = service.startSession(profile: profile)
        let webView = MockBrowserWebView()
        service.attach(webView: webView, to: session.record.id)

        try await service.execute(.open(URL(string: "https://www.opentable.com")!), sessionID: session.record.id, profileId: profile.profileId)
        try await service.execute(.reload, sessionID: session.record.id, profileId: profile.profileId)
        webView.canNavigateBack = true
        try await service.execute(.goBack, sessionID: session.record.id, profileId: profile.profileId)
        webView.canNavigateForward = true
        try await service.execute(.goForward, sessionID: session.record.id, profileId: profile.profileId)

        #expect(webView.loadedRequests.count == 1)
        #expect(webView.loadedRequests.first?.url?.absoluteString == "https://www.opentable.com")
        #expect(webView.didReload)
        #expect(webView.didGoBack)
        #expect(webView.didGoForward)
        #expect(session.record.currentURL == "https://www.opentable.com")
    }

    @MainActor
    @Test
    func browserAutomationServiceRejectsProfileMismatch() async throws {
        let profile = BrowserProfile()
        let service = BrowserAutomationService()
        let session = service.startSession(profile: profile)
        let webView = MockBrowserWebView()
        service.attach(webView: webView, to: session.record.id)

        await #expect(throws: BrowserPolicyEnforcerError.self) {
            try await service.execute(.reload, sessionID: session.record.id, profileId: "other-profile")
        }
    }

    @MainActor
    @Test
    func browserAutomationServiceBlocksDisallowedHost() async throws {
        let paths = makePaths()
        let registry = BrowserPolicyRegistry(paths: paths)
        try registry.save(
            BrowserRegistryDocument(
                profiles: [BrowserProfileRecord.default()],
                policies: [
                    BrowserPolicyRecord(
                        profileId: "default",
                        displayName: "Default Browser",
                        allowedHosts: ["www.opentable.com"],
                        confirmationRules: [],
                        notes: nil
                    )
                ],
                updatedAt: Date()
            )
        )
        let confirmationStore = BrowserConfirmationStore(paths: paths)
        let service = BrowserAutomationService(
            policyEnforcer: BrowserPolicyEnforcer(),
            policyRegistry: registry,
            confirmationStore: confirmationStore
        )
        let profile = BrowserProfile()
        let session = service.startSession(profile: profile)
        let webView = MockBrowserWebView()
        webView.currentURL = URL(string: "https://www.example.com")!
        service.attach(webView: webView, to: session.record.id)

        await #expect(throws: BrowserPolicyEnforcerError.self) {
            try await service.execute(.reload, sessionID: session.record.id, profileId: profile.profileId)
        }
    }

    @MainActor
    @Test
    func browserAutomationServiceCreatesAndResolvesConfirmation() async throws {
        let paths = makePaths()
        let registry = BrowserPolicyRegistry(paths: paths)
        try registry.save(
            BrowserRegistryDocument(
                profiles: [BrowserProfileRecord.default()],
                policies: [
                    BrowserPolicyRecord(
                        profileId: "default",
                        displayName: "Default Browser",
                        allowedHosts: [],
                        confirmationRules: [BrowserConfirmationRule(actionType: .submit, hostPattern: nil, notes: nil)],
                        notes: nil
                    )
                ],
                updatedAt: Date()
            )
        )
        let confirmationStore = BrowserConfirmationStore(paths: paths)
        let service = BrowserAutomationService(
            policyEnforcer: BrowserPolicyEnforcer(),
            policyRegistry: registry,
            confirmationStore: confirmationStore
        )
        let profile = BrowserProfile()
        let session = service.startSession(profile: profile)
        let webView = MockBrowserWebView()
        webView.currentURL = URL(string: "https://www.opentable.com/reserve")!
        service.attach(webView: webView, to: session.record.id)

        await #expect(throws: BrowserPolicyEnforcerError.self) {
            try await service.execute(.submit(targetID: "el_3"), sessionID: session.record.id, profileId: profile.profileId)
        }

        #expect(service.pendingConfirmation?.resolution == .pending)
        #expect(session.mode == .awaitingConfirmation)

        try service.resolveConfirmation(sessionID: session.record.id, resolution: .approved)
        #expect(service.pendingConfirmation == nil)
        #expect(session.mode == .agentControlling)

        webView.nextEvaluationResult = ["ok": true]
        try await service.execute(.submit(targetID: "el_3"), sessionID: session.record.id, profileId: profile.profileId)

        await #expect(throws: BrowserPolicyEnforcerError.self) {
            try await service.execute(.submit(targetID: "el_3"), sessionID: session.record.id, profileId: profile.profileId)
        }
        try service.resolveConfirmation(sessionID: session.record.id, resolution: .takeOver)
        #expect(session.mode == .manual)
    }

    @MainActor
    @Test
    func browserAutomationServiceBuildsPageSnapshotFromInspection() async throws {
        let profile = BrowserProfile()
        let service = BrowserAutomationService()
        let session = service.startSession(profile: profile)
        let webView = MockBrowserWebView()
        webView.nextEvaluationResult = [
            "currentURL": "https://www.opentable.com/r/demo",
            "title": "OpenTable",
            "isLoading": false,
            "visibleTextSummary": "Tables available at 2:00 PM and 3:00 PM",
            "actionableElements": [
                [
                    "id": "el_0",
                    "role": "button",
                    "label": "Find a Table",
                    "value": NSNull(),
                    "disabled": false,
                    "hidden": false,
                    "cssSelector": "#find-table",
                    "textAnchor": "Find a Table",
                    "domPath": "button"
                ]
            ]
        ]
        service.attach(webView: webView, to: session.record.id)

        let snapshot = try await service.inspectPage(sessionID: session.record.id)

        #expect(snapshot.currentURL == "https://www.opentable.com/r/demo")
        #expect(snapshot.visibleTextSummary.contains("2:00 PM"))
        #expect(snapshot.actionableElements.count == 1)
        #expect(snapshot.actionableElements.first?.id == "el_0")
    }

    @MainActor
    @Test
    func browserAutomationServiceExecutesTargetedActions() async throws {
        let profile = BrowserProfile()
        let service = BrowserAutomationService()
        let session = service.startSession(profile: profile)
        let webView = MockBrowserWebView()
        webView.nextEvaluationResult = ["ok": true]
        service.attach(webView: webView, to: session.record.id)

        try await service.execute(.click(targetID: "el_1"), sessionID: session.record.id, profileId: profile.profileId)
        try await service.execute(.fill(targetID: "el_2", value: "2"), sessionID: session.record.id, profileId: profile.profileId)

        #expect(webView.evaluatedScripts.count == 2)
        #expect(webView.evaluatedScripts[0].contains("data-agenthub-target-id=\"el_1\""))
        #expect(webView.evaluatedScripts[1].contains("value = \"2\""))
    }

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
        let manual = orchestrator.computeNextRun(after: now, scheduleType: .manual, scheduleValue: "")
        let interval = orchestrator.computeNextRun(after: now, scheduleType: .intervalMinutes, scheduleValue: "30")

        #expect(manual == nil)
        #expect(interval != nil)
        #expect(abs(interval!.timeIntervalSince(now) - 1800) < 1)
    }

    @Test
    func browserViewModelTracksNavigationStateAndCloseResetsIt() {
        let viewModel = BrowserViewModel(profile: BrowserProfile())
        let url = URL(string: "https://www.opentable.com")!

        viewModel.open(url: url)
        #expect(viewModel.currentURL == url)

        viewModel.updateNavigationState(
            currentURL: url,
            pageTitle: "OpenTable",
            isLoading: true,
            canGoBack: true,
            canGoForward: false
        )

        #expect(viewModel.pageTitle == "OpenTable")
        #expect(viewModel.isLoading)
        #expect(viewModel.canGoBack)
        #expect(!viewModel.canGoForward)

        viewModel.close()

        #expect(viewModel.currentURL == nil)
        #expect(viewModel.pageTitle.isEmpty)
        #expect(!viewModel.isLoading)
        #expect(!viewModel.canGoBack)
        #expect(!viewModel.canGoForward)
    }

}

@MainActor
private final class MockBrowserWebView: BrowserWebViewControlling {
    var currentURL: URL?
    var pageTitle = ""
    var isLoadingPage = false
    var canNavigateBack = false
    var canNavigateForward = false

    var loadedRequests: [URLRequest] = []
    var evaluatedScripts: [String] = []
    var nextEvaluationResult: Any?
    var didGoBack = false
    var didGoForward = false
    var didReload = false

    func loadRequest(_ request: URLRequest) {
        loadedRequests.append(request)
        currentURL = request.url
    }

    func navigateBack() {
        didGoBack = true
    }

    func navigateForward() {
        didGoForward = true
    }

    func reloadPage() {
        didReload = true
    }

    func evaluate(script: String) async throws -> Any? {
        evaluatedScripts.append(script)
        return nextEvaluationResult
    }
}

private func makePaths() -> AppPaths {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentHubBrowserAutomationTests-\(UUID().uuidString)", isDirectory: true)
    return AppPaths(root: root)
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
