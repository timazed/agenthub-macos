import Foundation
import Testing
@testable import AgentHub

struct AppUpdateWorkloadMonitorTests {
    @Test
    func reportsBusyWhenAnyTaskIsRunning() throws {
        let paths = try makePaths()
        let taskStore = try TaskStore(paths: paths)
        try taskStore.upsert(makeTask(state: .running))
        try taskStore.upsert(makeTask(state: .scheduled))

        let monitor = AppUpdateWorkloadMonitor(taskStore: taskStore)
        let workload = try monitor.currentState()

        #expect(workload.isBusy)
        #expect(workload.reason == .runningTask)
    }

    @Test
    func reportsIdleWhenNoTaskIsRunning() throws {
        let paths = try makePaths()
        let taskStore = try TaskStore(paths: paths)
        try taskStore.upsert(makeTask(state: .scheduled))
        try taskStore.upsert(makeTask(state: .completed))

        let monitor = AppUpdateWorkloadMonitor(taskStore: taskStore)
        let workload = try monitor.currentState()

        #expect(workload == .idle)
    }

    private func makePaths() throws -> AppPaths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppUpdateWorkloadMonitorTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        try paths.prepare()
        return paths
    }

    private func makeTask(state: TaskState) -> TaskRecord {
        TaskRecord(
            id: UUID(),
            title: "Task \(state.rawValue)",
            instructions: "Do work",
            scheduleType: .manual,
            scheduleValue: "",
            state: state,
            codexThreadId: nil,
            personaId: "default",
            runtimeMode: .chatOnly,
            repoPath: nil,
            createdAt: .now,
            updatedAt: .now,
            lastRun: nil,
            nextRun: nil,
            lastError: nil
        )
    }
}
