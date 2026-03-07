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
        _ = try? configStore.loadOrCreateDefault()
        let chatSessionService = ChatSessionService(
            sessionStore: sessionStore,
            personaManager: personaManager,
            runtime: runtime,
            paths: paths,
            runtimeConfigStore: configStore
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
            runtimeFactory: { PreviewCodexRuntime() }
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
        _ = try? configStore.loadOrCreateDefault()
        let orchestrator = TaskOrchestrator(
            taskStore: taskStore,
            taskRunStore: taskRunStore,
            activityLogStore: activityLogStore,
            personaManager: personaManager,
            workspaceManager: WorkspaceManager(),
            paths: paths,
            runtimeConfigStore: configStore,
            runtimeFactory: { PreviewCodexRuntime() }
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

private final class PreviewCodexRuntime: CodexRuntime {
    func startNewThread(prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        CodexExecutionResult(threadId: "preview-thread", exitCode: 0, stdout: "", stderr: "")
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

private struct ChatSurfacePreviewHost: View {
    @StateObject private var viewModel = PreviewFactory.makeChatViewModel()

    var body: some View {
        ChatView(viewModel: viewModel, isPanelPresented: false, onTogglePanel: {})
            .frame(width: 1120, height: 760)
            .padding()
            .background(Color.black)
    }
}

private struct ChatBusyPreviewHost: View {
    @StateObject private var viewModel = PreviewFactory.makeBusyChatViewModel()

    var body: some View {
        ChatView(viewModel: viewModel, isPanelPresented: true, onTogglePanel: {})
            .frame(width: 1120, height: 760)
            .padding()
            .background(Color.black)
    }
}

private struct TaskDrawerPreviewHost: View {
    @StateObject private var tasksViewModel = PreviewFactory.makeTasksViewModel()
    @StateObject private var activityViewModel = PreviewFactory.makeActivityViewModel()

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.92)
            AssistantPanelView(
                tasksViewModel: tasksViewModel,
                activityViewModel: activityViewModel,
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
