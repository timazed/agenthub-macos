import Foundation

enum AppUpdateBusyReason: String, Equatable {
    case runningTask = "running-task"
}

struct AppUpdateWorkloadState: Equatable {
    var isBusy: Bool
    var reason: AppUpdateBusyReason?

    static let idle = AppUpdateWorkloadState(isBusy: false, reason: nil)
}

protocol AppUpdateWorkloadMonitoring {
    func currentState() throws -> AppUpdateWorkloadState
}

final class AppUpdateWorkloadMonitor: AppUpdateWorkloadMonitoring {
    private let taskStore: TaskStore

    init(taskStore: TaskStore) {
        self.taskStore = taskStore
    }

    func currentState() throws -> AppUpdateWorkloadState {
        let tasks = try taskStore.load()
        if tasks.contains(where: { $0.state == .running }) {
            return AppUpdateWorkloadState(isBusy: true, reason: .runningTask)
        }

        return .idle
    }
}
