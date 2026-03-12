import Foundation
import Sparkle
import Testing
@testable import AgentHub

@MainActor
struct AppUpdateTaskTests {
    @Test
    func defersRelaunchWhenWorkIsRunning() {
        let monitor = StubWorkloadMonitor()
        monitor.state = AppUpdateWorkloadState(isBusy: true, reason: .runningTask)
        let logger = SpyAppUpdateLogger()
        let coordinator = AppUpdateTask(
            workloadMonitor: monitor,
            logger: logger,
            pollIntervalNanoseconds: nil
        )

        var didInvokeInstall = false
        let deferred = coordinator.shouldDeferRelaunch(
            for: makeAppcastItem(version: "1.2.3"),
            installHandler: { didInvokeInstall = true }
        )

        #expect(deferred)
        #expect(!didInvokeInstall)
        #expect(coordinator.phase == .installDeferred)
        #expect(logger.messages.contains(where: { $0.contains("install_deferred") }))
    }

    @Test
    func resumesDeferredInstallWhenAppBecomesIdle() {
        let monitor = StubWorkloadMonitor()
        monitor.state = AppUpdateWorkloadState(isBusy: true, reason: .runningTask)
        let logger = SpyAppUpdateLogger()
        let coordinator = AppUpdateTask(
            workloadMonitor: monitor,
            logger: logger,
            pollIntervalNanoseconds: nil
        )

        var didInvokeInstall = false
        let deferred = coordinator.shouldDeferInstallOnQuit(
            for: makeAppcastItem(version: "2.0"),
            installHandler: { didInvokeInstall = true }
        )
        #expect(deferred)

        monitor.state = .idle
        let resumed = coordinator.processDeferredInstallIfIdle()

        #expect(resumed)
        #expect(didInvokeInstall)
        #expect(coordinator.phase == .installing)
        #expect(logger.messages.contains(where: { $0.contains("deferred_install_resumed") }))
    }

    @Test
    func defersInstallConservativelyWhenWorkloadLookupFails() {
        let monitor = StubWorkloadMonitor()
        monitor.error = StubError.lookupFailed
        let logger = SpyAppUpdateLogger()
        let coordinator = AppUpdateTask(
            workloadMonitor: monitor,
            logger: logger,
            pollIntervalNanoseconds: nil
        )

        let deferred = coordinator.shouldDeferInstallOnQuit(
            for: makeAppcastItem(version: "2.1"),
            installHandler: {}
        )

        #expect(deferred)
        #expect(coordinator.phase == .installDeferred)
        #expect(logger.messages.contains(where: { $0.contains("monitor_error") }))
    }

    private func makeAppcastItem(version: String) -> SUAppcastItem {
        SUAppcastItem(dictionary: [
            "sparkle:shortVersionString": version,
            "enclosure": [
                "sparkle:version": version,
                "sparkle:shortVersionString": version,
                "url": "https://example.com/AgentHub-\(version).zip",
                "length": "123"
            ]
        ])!
    }
}

private final class StubWorkloadMonitor: AppUpdateWorkloadMonitoring {
    var state: AppUpdateWorkloadState = .idle
    var error: Error?

    func currentState() throws -> AppUpdateWorkloadState {
        if let error {
            throw error
        }
        return state
    }
}

private final class SpyAppUpdateLogger: AppUpdateLogging {
    private(set) var messages: [String] = []

    func log(_ message: String) {
        messages.append(message)
    }
}

private enum StubError: Error {
    case lookupFailed
}
