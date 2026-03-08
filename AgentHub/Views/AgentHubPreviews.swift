import Foundation
import SwiftUI

private enum PreviewFactory {
    static func makePaths() -> AppPaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentHubPreview", isDirectory: true)
        return AppPaths(root: root)
    }

    @MainActor
    static func makeChatViewModel() -> ChatViewModel {
        let paths = makePaths()
        try? paths.prepare()

        let sessionStore = AssistantSessionStore(paths: paths)
        let personaManager = PersonaManager(paths: paths)
        let runtime = PreviewCodexRuntime()
        let configStore = AppRuntimeConfigStore(paths: paths)
        let authStore = AuthStore(paths: paths)
        _ = try? configStore.loadOrCreateDefault()
        _ = try? authStore.loadOrCreateDefault()
        let authManager = AuthManager(
            store: authStore,
            providerClient: CodexAuthProviderClient(runtime: runtime, paths: paths)
        )
        let chatSessionService = ChatSessionService(
            sessionStore: sessionStore,
            personaManager: personaManager,
            runtime: runtime,
            paths: paths,
            runtimeConfigStore: configStore,
            authManager: authManager
        )

        let taskStore = (try? TaskStore(paths: paths)) ?? fatalTaskStore(paths: paths)
        let taskRunStore = TaskRunStore(paths: paths)
        let activityLogStore = ActivityLogStore(paths: paths)
        let taskOrchestrator = TaskOrchestrator(
            taskStore: taskStore,
            taskRunStore: taskRunStore,
            activityLogStore: activityLogStore,
            personaManager: personaManager,
            workspaceManager: WorkspaceManager(),
            paths: paths,
            runtimeConfigStore: configStore,
            authManager: authManager,
            runtimeFactory: { runtime }
        )

        let viewModel = ChatViewModel(
            chatSessionService: chatSessionService,
            taskOrchestrator: taskOrchestrator,
            runtimeConfigStore: configStore,
            personaManager: personaManager
        )
        viewModel.messages = sampleMessages()
        viewModel.pendingProposal = sampleProposal()
        return viewModel
    }

    @MainActor
    static func makeAuthViewModel(authenticated: Bool) -> AuthViewModel {
        let paths = makePaths()
        try? paths.prepare()

        let authStore = AuthStore(paths: paths)
        let runtime = PreviewCodexRuntime()
        let authManager = AuthManager(
            store: authStore,
            providerClient: CodexAuthProviderClient(runtime: runtime, paths: paths)
        )
        let state = AuthState(
            status: authenticated ? .authenticated : .unauthenticated,
            accountLabel: authenticated ? "preview@example.com" : nil,
            lastValidatedAt: authenticated ? Date() : nil,
            failureReason: authenticated ? nil : "Sign in before using AgentHub.",
            updatedAt: Date()
        )
        try? authStore.save(state)

        return AuthViewModel(
            authManager: authManager,
            initialState: state,
            openURL: { _ in true }
        )
    }

    @MainActor
    static func makeBusyChatViewModel() -> ChatViewModel {
        let viewModel = makeChatViewModel()
        viewModel.pendingProposal = nil
        viewModel.isBusy = true
        return viewModel
    }

    @MainActor
    static func makeTasksViewModel() -> TasksViewModel {
        let paths = makePaths()
        try? paths.prepare()

        let personaManager = PersonaManager(paths: paths)
        let taskStore = (try? TaskStore(paths: paths)) ?? fatalTaskStore(paths: paths)
        let taskRunStore = TaskRunStore(paths: paths)
        let activityLogStore = ActivityLogStore(paths: paths)
        let configStore = AppRuntimeConfigStore(paths: paths)
        let authStore = AuthStore(paths: paths)
        _ = try? configStore.loadOrCreateDefault()
        _ = try? authStore.loadOrCreateDefault()
        let runtime = PreviewCodexRuntime()
        let authManager = AuthManager(
            store: authStore,
            providerClient: CodexAuthProviderClient(runtime: runtime, paths: paths)
        )
        let orchestrator = TaskOrchestrator(
            taskStore: taskStore,
            taskRunStore: taskRunStore,
            activityLogStore: activityLogStore,
            personaManager: personaManager,
            workspaceManager: WorkspaceManager(),
            paths: paths,
            runtimeConfigStore: configStore,
            authManager: authManager,
            runtimeFactory: { runtime }
        )
        let scheduleRunner = ScheduleRunner(taskStore: taskStore, orchestrator: orchestrator, paths: paths)
        let viewModel = TasksViewModel(taskOrchestrator: orchestrator, scheduleRunner: scheduleRunner, appExecutableURL: URL(fileURLWithPath: "/Applications/AgentHub.app/Contents/MacOS/AgentHub"))
        viewModel.tasks = sampleTasks()
        return viewModel
    }

    @MainActor
    static func makeActivityViewModel() -> ActivityLogViewModel {
        let viewModel = ActivityLogViewModel(store: ActivityLogStore(paths: makePaths()))
        viewModel.events = sampleEvents()
        return viewModel
    }

    @MainActor
    static func makeIMessageViewModel() -> IMessageIntegrationViewModel {
        let paths = makePaths()
        try? paths.prepare()

        let configStore = IMessageIntegrationConfigStore(paths: paths)
        let whitelistService = IMessageWhitelistService()
        let activityStore = ActivityLogStore(paths: paths)
        let personaManager = PersonaManager(paths: paths)
        let router = IMessageCommandRouter(
            configStore: configStore,
            whitelistService: whitelistService,
            mentionParser: IMessageMentionParser(personaManager: personaManager),
            executionService: ExternalAgentExecutionService(
                runtimeConfigStore: AppRuntimeConfigStore(paths: paths),
                sessionStore: AssistantSessionStore(paths: paths),
                paths: paths,
                runtimeFactory: { PreviewCodexRuntime() }
            ),
            replyService: IMessageReplyService(),
            activityLogStore: activityStore,
            sessionStore: AssistantSessionStore(paths: paths),
            personaManager: personaManager
        )
        let monitor = IMessageMonitorService(
            configStore: configStore,
            router: router,
            activityLogStore: activityStore
        )
        let viewModel = IMessageIntegrationViewModel(
            configStore: configStore,
            whitelistService: whitelistService,
            monitorService: monitor,
            permissionService: IMessagePermissionService()
        )
        viewModel.load()
        return viewModel
    }

    static func sampleMessages() -> [Message] {
        let sessionID = UUID()
        return [
            Message(id: UUID(), sessionId: sessionID, role: .assistant, text: "You finally opened the app. Brave.", source: .codexStdout, createdAt: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()),
            Message(id: UUID(), sessionId: sessionID, role: .assistant, text: "Current status: background tasks are quiet, schedules are intact, and nothing is on fire yet.", source: .codexStdout, createdAt: Calendar.current.date(byAdding: .hour, value: -8, to: Date()) ?? Date()),
            Message(id: UUID(), sessionId: sessionID, role: .user, text: "Summarize what AgentHub is doing for me.", source: .userInput, createdAt: Calendar.current.date(byAdding: .minute, value: -3, to: Date()) ?? Date()),
            Message(id: UUID(), sessionId: sessionID, role: .assistant, text: "Right now it is acting like a polite personal operator: chat first, scheduled tasks on the side, and just enough structure to keep the chaos searchable.", source: .codexStdout, createdAt: Calendar.current.date(byAdding: .minute, value: -2, to: Date()) ?? Date())
        ]
    }

    static func sampleTasks() -> [TaskRecord] {
        let now = Date()
        return [
            TaskRecord(id: UUID(), title: "Morning briefing", instructions: "Check calendar, unread messages, and open tasks. Return a concise summary.", scheduleType: .dailyAtHHMM, scheduleValue: "08:00", state: .scheduled, codexThreadId: "thread-1", personaId: "default", runtimeMode: .chatOnly, repoPath: nil, createdAt: now, updatedAt: now, lastRun: Calendar.current.date(byAdding: .day, value: -1, to: now), nextRun: Calendar.current.date(byAdding: .hour, value: 9, to: now), lastError: nil),
            TaskRecord(id: UUID(), title: "Rental monitor", instructions: "Scan Bondi rentals under budget and report only changes.", scheduleType: .intervalMinutes, scheduleValue: "120", state: .needsInput, codexThreadId: "thread-2", personaId: "default", runtimeMode: .chatOnly, repoPath: nil, createdAt: now, updatedAt: now, lastRun: Calendar.current.date(byAdding: .hour, value: -3, to: now), nextRun: Calendar.current.date(byAdding: .hour, value: 2, to: now), lastError: "Needs suburb clarification"),
            TaskRecord(id: UUID(), title: "Trip checklist", instructions: "Keep a lightweight travel checklist and nudge when anything is missing.", scheduleType: .manual, scheduleValue: "", state: .paused, codexThreadId: nil, personaId: "default", runtimeMode: .chatOnly, repoPath: nil, createdAt: now, updatedAt: now, lastRun: nil, nextRun: nil, lastError: nil),
            TaskRecord(id: UUID(), title: "Invoice follow-up", instructions: "Track unpaid invoices and report only overdue items.", scheduleType: .dailyAtHHMM, scheduleValue: "15:30", state: .error, codexThreadId: "thread-3", personaId: "default", runtimeMode: .chatOnly, repoPath: nil, createdAt: now, updatedAt: now, lastRun: Calendar.current.date(byAdding: .day, value: -2, to: now), nextRun: nil, lastError: "Remote source unavailable")
        ]
    }

    static func sampleEvents() -> [ActivityEvent] {
        let now = Date()
        return [
            ActivityEvent(id: UUID(), taskId: nil, kind: .assistantAction, message: "Assistant thread resumed", createdAt: Calendar.current.date(byAdding: .minute, value: -2, to: now) ?? now),
            ActivityEvent(id: UUID(), taskId: nil, kind: .taskRunCompleted, message: "Morning briefing completed a run", createdAt: Calendar.current.date(byAdding: .hour, value: -2, to: now) ?? now),
            ActivityEvent(id: UUID(), taskId: nil, kind: .taskNeedsInput, message: "Rental monitor needs input", createdAt: Calendar.current.date(byAdding: .hour, value: -5, to: now) ?? now)
        ]
    }

    static func sampleProposal() -> TaskProposal {
        TaskProposal(
            id: UUID(),
            title: "Daily market pulse",
            instructions: "Check major tech and crypto headlines every morning and summarize only the meaningful moves.",
            scheduleType: .dailyAtHHMM,
            scheduleValue: "08:30",
            runtimeMode: .chatOnly,
            repoPath: nil,
            runNow: false
        )
    }

    private static func fatalTaskStore(paths: AppPaths) -> TaskStore {
        do {
            return try TaskStore(paths: paths)
        } catch {
            fatalError("Failed to create preview TaskStore: \(error.localizedDescription)")
        }
    }
}

private final class PreviewCodexRuntime: AssistantRuntime {
    func startNewThread(prompt: String, config: AssistantLaunchConfig) async throws -> AssistantExecutionResult {
        AssistantExecutionResult(threadId: "preview-thread", exitCode: 0, stdout: "", stderr: "")
    }

    func resumeThread(threadId: String, prompt: String, config: AssistantLaunchConfig) async throws -> AssistantExecutionResult {
        AssistantExecutionResult(threadId: threadId, exitCode: 0, stdout: "", stderr: "")
    }

    func checkLoginStatus(codexHome: String) throws -> AssistantLoginStatusResult {
        AssistantLoginStatusResult(
            isAuthenticated: true,
            accountEmail: "preview@example.com",
            message: "Logged in as preview@example.com"
        )
    }

    func streamEvents() -> AsyncStream<AssistantEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRun() throws {}
}

private struct ChatSurfacePreviewHost: View {
    @StateObject private var viewModel = PreviewFactory.makeChatViewModel()

    var body: some View {
        ChatView(viewModel: viewModel, isPanelPresented: false, onTogglePanel: {}, isInputEnabled: true, blockedMessage: nil)
            .frame(width: 1120, height: 760)
            .padding()
            .background(Color.black)
    }
}

private struct ChatBusyPreviewHost: View {
    @StateObject private var viewModel = PreviewFactory.makeBusyChatViewModel()

    var body: some View {
        ChatView(viewModel: viewModel, isPanelPresented: true, onTogglePanel: {}, isInputEnabled: true, blockedMessage: nil)
            .frame(width: 1120, height: 760)
            .padding()
            .background(Color.black)
    }
}

private struct LoginGatePreviewHost: View {
    @StateObject private var viewModel = PreviewFactory.makeAuthViewModel(authenticated: false)

    var body: some View {
        CodexLoginGateView(
            viewModel: viewModel,
            onStartLogin: {},
            onRetryStatus: {},
            onCancelLogin: {}
        )
        .frame(width: 1120, height: 760)
    }
}

private struct TaskDrawerPreviewHost: View {
    @StateObject private var tasksViewModel = PreviewFactory.makeTasksViewModel()
    @StateObject private var activityViewModel = PreviewFactory.makeActivityViewModel()
    @StateObject private var iMessageViewModel = PreviewFactory.makeIMessageViewModel()

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.92)
            AssistantPanelView(
                tasksViewModel: tasksViewModel,
                activityViewModel: activityViewModel,
                iMessageViewModel: iMessageViewModel,
                onClose: {},
                onAddTask: {},
                onEditTask: { _ in }
            )
            .padding(24)
        }
        .frame(width: 520, height: 760)
    }
}

struct ChatSurfacePreview: PreviewProvider {
    static var previews: some View {
        ChatSurfacePreviewHost()
            .previewDisplayName("Chat Surface")
    }
}

struct ChatBusyPreview: PreviewProvider {
    static var previews: some View {
        ChatBusyPreviewHost()
            .previewDisplayName("Chat Surface Busy")
    }
}

struct TaskDrawerPreview: PreviewProvider {
    static var previews: some View {
        TaskDrawerPreviewHost()
            .previewDisplayName("Task Drawer")
    }
}

struct TaskEditorPreview: PreviewProvider {
    static var previews: some View {
        TaskEditorSheetView(task: PreviewFactory.sampleTasks().first, onSave: { _, _ in }, onCancel: {})
            .frame(width: 760, height: 620)
            .previewDisplayName("Task Editor")
    }
}

struct LoginGatePreview: PreviewProvider {
    static var previews: some View {
        LoginGatePreviewHost()
            .previewDisplayName("Codex Login Gate")
    }
}
