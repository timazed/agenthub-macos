import SwiftUI

struct AppShellView: View {
    @StateObject private var appViewModel = AppViewModel()
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var tasksViewModel: TasksViewModel
    @StateObject private var activityViewModel: ActivityLogViewModel
    @StateObject private var iMessageViewModel: IMessageIntegrationViewModel
    @State private var didPerformInitialLoad = false

    init(container: AppContainer) {
        _authViewModel = StateObject(wrappedValue: AuthViewModel(
            authManager: container.authManager,
            initialState: (try? container.authManager.loadCachedState()) ?? .default()
        ))
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(
            chatSessionService: container.chatSessionService,
            taskOrchestrator: container.taskOrchestrator,
            runtimeConfigStore: container.runtimeConfigStore,
            personaManager: container.personaManager
        ))
        _tasksViewModel = StateObject(wrappedValue: TasksViewModel(
            taskOrchestrator: container.taskOrchestrator,
            scheduleRunner: container.scheduleRunner,
            appExecutableURL: container.appExecutableURL
        ))
        _activityViewModel = StateObject(wrappedValue: ActivityLogViewModel(store: container.activityLogStore))
        _iMessageViewModel = StateObject(wrappedValue: IMessageIntegrationViewModel(
            configStore: container.iMessageIntegrationConfigStore,
            whitelistService: container.iMessageWhitelistService,
            monitorService: container.iMessageMonitorService,
            permissionService: IMessagePermissionService()
        ))
    }

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                ChatView(
                    viewModel: chatViewModel,
                    isPanelPresented: appViewModel.isPanelPresented,
                    onTogglePanel: { appViewModel.togglePanel() },
                    isInputEnabled: true,
                    blockedMessage: nil
                )
                .frame(minWidth: 400)
            } else {
                CodexLoginGateView(
                    viewModel: authViewModel,
                    onStartLogin: {
                        Task {
                            await authViewModel.beginLogin()
                            performInitialLoadIfNeeded()
                        }
                    },
                    onRetryStatus: {
                        Task {
                            await authViewModel.refreshStatus()
                            performInitialLoadIfNeeded()
                        }
                    },
                    onCancelLogin: { authViewModel.cancelLogin() }
                )
                .frame(minWidth: 400)
            }
        }
        .inspector(isPresented: $appViewModel.isPanelPresented) {
            AssistantPanelView(
                tasksViewModel: tasksViewModel,
                activityViewModel: activityViewModel,
                iMessageViewModel: iMessageViewModel,
                onClose: { appViewModel.isPanelPresented = false },
                onAddTask: { appViewModel.openEditor(for: nil) },
                onEditTask: { task in appViewModel.openEditor(for: task) }
            )
            .inspectorColumnWidth(min: 320, ideal: 392, max: 480)
        }
        .task {
            guard !didPerformInitialLoad else { return }
            await authViewModel.performStartupCheckIfNeeded()
            performInitialLoadIfNeeded()
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
        chatViewModel.errorMessage ?? tasksViewModel.errorMessage ?? activityViewModel.errorMessage ?? iMessageViewModel.errorMessage
    }

    private func performInitialLoadIfNeeded() {
        guard authViewModel.isAuthenticated, !didPerformInitialLoad else { return }
        didPerformInitialLoad = true
        tasksViewModel.load()
        activityViewModel.load()
        iMessageViewModel.load()
        chatViewModel.load()
        tasksViewModel.reconcileSchedulesDeferred()

        chatViewModel.onTasksChanged = {
            tasksViewModel.load()
            tasksViewModel.reconcileSchedulesDeferred()
        }
        chatViewModel.onActivityChanged = {
            activityViewModel.load()
        }
        tasksViewModel.onMutation = {
            activityViewModel.load()
        }
    }
}
