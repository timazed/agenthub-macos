import SwiftUI

struct AppShellView: View {
    @StateObject private var appViewModel = AppViewModel()
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var tasksViewModel: TasksViewModel
    @StateObject private var activityViewModel: ActivityLogViewModel
    @State private var didPerformInitialLoad = false

    init(container: AppContainer) {
        _authViewModel = StateObject(wrappedValue: AuthViewModel(
            authManager: container.authManager,
            initialState: (try? container.authManager.loadCachedState()) ?? .default(),
            onboardingManager: container.onboardingManager,
            initialOnboardingState: (try? container.onboardingManager.loadState()) ?? .default()
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
    }

    var body: some View {
        ZStack {
            OnboardingExperienceBackground()

            Group {
                if authViewModel.hasResolvedStartupCheck && authViewModel.hasCompletedOnboarding {
                    ChatView(
                        viewModel: chatViewModel,
                        isPanelPresented: appViewModel.isPanelPresented,
                        onTogglePanel: { appViewModel.togglePanel() },
                        isInputEnabled: true,
                        blockedMessage: nil
                    )
                    .frame(minWidth: 400)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
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
                        onCancelLogin: { authViewModel.cancelLogin() },
                        onUseDefaultPersonality: {
                            authViewModel.useDefaultPersonality()
                            performInitialLoadIfNeeded()
                        },
                        onSavePersonality: { personality in
                            authViewModel.savePersonality(personality)
                            performInitialLoadIfNeeded()
                        },
                        onSaveAgentName: { name in
                            authViewModel.saveAgentName(name)
                            performInitialLoadIfNeeded()
                        }
                    )
                    .frame(minWidth: 400)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: authViewModel.hasCompletedOnboarding)
        }
        .background(AdaptiveWindowBackground())
        .liquidGlass()
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
        chatViewModel.errorMessage ?? tasksViewModel.errorMessage ?? activityViewModel.errorMessage
    }

    private func performInitialLoadIfNeeded() {
        guard authViewModel.hasCompletedOnboarding, !didPerformInitialLoad else { return }
        didPerformInitialLoad = true
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
        tasksViewModel.onMutation = {
            activityViewModel.load()
        }
    }
}
