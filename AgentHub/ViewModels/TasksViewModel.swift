import Foundation
import Combine

@MainActor
final class TasksViewModel: ObservableObject {
    @Published var tasks: [TaskRecord] = []
    @Published var errorMessage: String?

    private let taskOrchestrator: TaskOrchestrator
    private let scheduleRunner: ScheduleRunner
    private let appExecutableURL: URL
    private var reconcileTask: Task<Void, Never>?

    var onMutation: (() -> Void)?

    init(taskOrchestrator: TaskOrchestrator, scheduleRunner: ScheduleRunner, appExecutableURL: URL) {
        self.taskOrchestrator = taskOrchestrator
        self.scheduleRunner = scheduleRunner
        self.appExecutableURL = appExecutableURL
    }

    var currentTasks: [TaskRecord] {
        tasks.filter { [.running, .scheduled, .needsInput].contains($0.state) }
    }

    var backlogTasks: [TaskRecord] {
        tasks.filter { [.paused, .completed, .error].contains($0.state) }
    }

    func load() {
        do {
            tasks = try taskOrchestrator.loadTasks()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reconcileSchedules() {
        do {
            try scheduleRunner.reconcileAll(appExecutableURL: appExecutableURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reconcileSchedulesDeferred() {
        reconcileTask?.cancel()
        let appExecutableURL = self.appExecutableURL
        let scheduleRunner = self.scheduleRunner

        reconcileTask = Task(priority: .utility) { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                try await scheduleRunner.reconcileAllAsync(appExecutableURL: appExecutableURL)

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.errorMessage = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func save(task: TaskRecord, isNew: Bool) {
        Task {
            do {
                if isNew {
                    let proposal = TaskProposal(
                        id: UUID(),
                        title: task.title,
                        instructions: task.instructions,
                        scheduleType: task.scheduleType,
                        scheduleValue: task.scheduleValue,
                        runtimeMode: task.runtimeMode,
                        repoPath: task.repoPath,
                        runNow: false
                    )
                    _ = try await taskOrchestrator.createTask(from: proposal)
                } else {
                    _ = try taskOrchestrator.updateTask(task)
                }
                load()
                reconcileSchedulesDeferred()
                onMutation?()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func runNow(task: TaskRecord) {
        Task {
            do {
                _ = try await taskOrchestrator.runTask(taskId: task.id)
                load()
                reconcileSchedulesDeferred()
                onMutation?()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func pause(task: TaskRecord) {
        do {
            _ = try taskOrchestrator.pauseTask(taskId: task.id)
            load()
            reconcileSchedulesDeferred()
            onMutation?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resume(task: TaskRecord) {
        do {
            _ = try taskOrchestrator.resumeTask(taskId: task.id)
            load()
            reconcileSchedulesDeferred()
            onMutation?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(task: TaskRecord) {
        do {
            try taskOrchestrator.deleteTask(taskId: task.id)
            load()
            reconcileSchedulesDeferred()
            onMutation?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reinitialize(task: TaskRecord) {
        do {
            _ = try taskOrchestrator.reinitializeThread(taskId: task.id)
            load()
            reconcileSchedulesDeferred()
            onMutation?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
