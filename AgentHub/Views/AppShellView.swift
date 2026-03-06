import SwiftUI

struct AppShellView: View {
    @StateObject private var appViewModel = AppViewModel()
    @StateObject private var browserViewModel: BrowserViewModel
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var tasksViewModel: TasksViewModel
    @StateObject private var activityViewModel: ActivityLogViewModel
    @State private var didPerformInitialLoad = false

    init(container: AppContainer) {
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
        ChatView(
            viewModel: chatViewModel,
            isPanelPresented: appViewModel.isPanelPresented,
            onTogglePanel: { appViewModel.togglePanel() }
        )
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
        .sheet(isPresented: $appViewModel.isBrowserPresented, onDismiss: {
            browserViewModel.close()
        }) {
            BrowserPlaceholderView(
                viewModel: browserViewModel,
                onClose: { appViewModel.closeBrowser() }
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
        tasksViewModel.onMutation = {
            activityViewModel.load()
        }
    }
}

private struct BrowserPlaceholderView: View {
    @ObservedObject var viewModel: BrowserViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Browser")
                        .font(.headline)
                    Text(viewModel.currentURL?.absoluteString ?? "No page selected yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
            }

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "safari")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Browser shell is wired")
                            .font(.headline)
                        Text("The embedded WebKit view and navigation controls will land in the next subtask.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                }
                .frame(minHeight: 320)
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 420)
    }
}
