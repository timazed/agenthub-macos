import SwiftUI

struct AppShellView: View {
    private let browserAutomationService: BrowserAutomationService
    @StateObject private var appViewModel = AppViewModel()
    @StateObject private var browserViewModel: BrowserViewModel
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var tasksViewModel: TasksViewModel
    @StateObject private var activityViewModel: ActivityLogViewModel
    @State private var didPerformInitialLoad = false

    init(container: AppContainer) {
        browserAutomationService = container.browserAutomationService
        _browserViewModel = StateObject(wrappedValue: container.browserViewModel)
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(
            chatSessionService: container.chatSessionService,
            taskOrchestrator: container.taskOrchestrator,
            runtimeConfigStore: container.runtimeConfigStore
        ))
        _tasksViewModel = StateObject(wrappedValue: TasksViewModel(
            taskOrchestrator: container.taskOrchestrator,
            scheduleRunner: container.scheduleRunner,
            appExecutableURL: container.appExecutableURL
        ))
        _activityViewModel = StateObject(wrappedValue: ActivityLogViewModel(store: container.activityLogStore))
    }

    var body: some View {
        content
        .inspector(isPresented: $appViewModel.isPanelPresented) {
            AssistantPanelView(
                tasksViewModel: tasksViewModel,
                activityViewModel: activityViewModel,
                onClose: { appViewModel.isPanelPresented = false },
                onAddTask: { appViewModel.openEditor(for: nil) },
                onEditTask: { task in appViewModel.openEditor(for: task) }
            )
            .inspectorColumnWidth(min: 320, ideal: 392, max: 480)
        }
        .task {
            guard !didPerformInitialLoad else { return }
            didPerformInitialLoad = true
            performInitialLoad()
        }
        .sheet(isPresented: $appViewModel.isEditorPresented, onDismiss: {
            tasksViewModel.load()
            tasksViewModel.reconcileSchedulesDeferred()
            activityViewModel.load()
        }) {
            TaskEditorSheetView(
                task: appViewModel.editingTask,
                onSave: { task, isNew in
                    tasksViewModel.save(task: task, isNew: isNew)
                    appViewModel.closeEditor()
                    activityViewModel.load()
                },
                onCancel: {
                    appViewModel.closeEditor()
                }
            )
        }
        .onReceive(browserAutomationService.$pendingConfirmation) { confirmation in
            if confirmation != nil {
                appViewModel.openBrowser()
            }
        }
        .alert("Error", isPresented: Binding(
            get: { combinedErrorMessage != nil },
            set: { show in
                if !show {
                    chatViewModel.errorMessage = nil
                    tasksViewModel.errorMessage = nil
                    activityViewModel.errorMessage = nil
                }
            }
        ), actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(combinedErrorMessage ?? "Unknown error")
        })
    }

    private var combinedErrorMessage: String? {
        chatViewModel.errorMessage ?? tasksViewModel.errorMessage ?? activityViewModel.errorMessage
    }

    private var content: some View {
        HSplitView {
            ChatView(
                viewModel: chatViewModel,
                isPanelPresented: appViewModel.isPanelPresented,
                isBrowserPresented: appViewModel.isBrowserPresented,
                onTogglePanel: { appViewModel.togglePanel() },
                onToggleBrowser: { appViewModel.toggleBrowser() },
                onOpenLink: { url in
                    browserViewModel.open(url: url)
                    appViewModel.openBrowser()
                }
            )

            if appViewModel.isBrowserPresented {
                BrowserView(
                    viewModel: browserViewModel,
                    automationService: browserAutomationService,
                    onClose: { appViewModel.closeBrowser() }
                )
                .frame(minWidth: 420, idealWidth: 520, maxWidth: 680, maxHeight: .infinity)
            }
        }
    }

    private func performInitialLoad() {
        tasksViewModel.load()
        activityViewModel.load()
        chatViewModel.load()
        tasksViewModel.reconcileSchedulesDeferred()

        chatViewModel.onTasksChanged = {
            tasksViewModel.load()
            tasksViewModel.reconcileSchedulesDeferred()
        }
        chatViewModel.onActivityChanged = {
            activityViewModel.load()
        }
        chatViewModel.onBrowserRequested = {
            appViewModel.openBrowser()
        }
        tasksViewModel.onMutation = {
            activityViewModel.load()
        }
    }
}
