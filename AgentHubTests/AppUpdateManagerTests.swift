import Foundation
import Sparkle
import Testing
@testable import AgentHub

@MainActor
struct AppUpdateManagerTests {
    @Test
    func startPerformsStartupCheckWhenConfigured() throws {
        let controller = FakeAppUpdateController()
        let manager = makeManager(
            controller: controller,
            configured: true
        )

        manager.start()

        #expect(manager.isConfigured)
        #expect(manager.canCheckForUpdates)
        #expect(manager.phase == .checking)
        #expect(controller.backgroundCheckCount == 1)
        #expect(controller.manualCheckCount == 0)
    }

    @Test
    func startSkipsControllerCreationWhenSparkleIsUnconfigured() throws {
        var factoryCalled = false
        let manager = try makeManager(
            controllerFactory: { _ in
                factoryCalled = true
                return FakeAppUpdateController()
            },
            configured: false
        )

        manager.start()

        #expect(!factoryCalled)
        #expect(!manager.isConfigured)
        #expect(!manager.canCheckForUpdates)
        #expect(manager.phase == .idle)
    }

    @Test
    func checkForUpdatesUsesManualControllerPath() throws {
        let controller = FakeAppUpdateController()
        let manager = makeManager(
            controller: controller,
            configured: true
        )
        manager.start()

        manager.checkForUpdates()

        #expect(manager.phase == .checking)
        #expect(controller.backgroundCheckCount == 1)
        #expect(controller.manualCheckCount == 1)
    }

    @Test
    func observedCanCheckForUpdatesChangesPropagateToPublishedState() throws {
        let controller = FakeAppUpdateController()
        let manager = makeManager(
            controller: controller,
            configured: true
        )
        manager.start()

        controller.sendCanCheckUpdate(false)

        #expect(!manager.canCheckForUpdates)
    }

    @Test
    func stopInvalidatesObservation() throws {
        let controller = FakeAppUpdateController()
        let manager = makeManager(
            controller: controller,
            configured: true
        )
        manager.start()

        manager.stop()

        #expect(controller.observation.invalidated)
    }

    private func makeManager(
        controller: FakeAppUpdateController,
        configured: Bool
    ) -> AppUpdateManager {
        makeManager(
            controllerFactory: { _ in controller },
            configured: configured
        )
    }

    private func makeManager(
        controllerFactory: @escaping (SPUUpdaterDelegate) -> any AppUpdateControlling,
        configured: Bool
    ) -> AppUpdateManager {
        let paths = makePaths()
        let logger = ManagerTestLogger()
        let task = AppUpdateTask(
            workloadMonitor: ManagerTestWorkloadMonitor(),
            logger: logger,
            pollIntervalNanoseconds: nil
        )

        return AppUpdateManager(
            bundle: .main,
            paths: paths,
            taskStore: try! TaskStore(paths: paths),
            activityLogStore: ActivityLogStore(paths: paths),
            appUpdateTask: task,
            configurationValidator: { _ in configured },
            controllerFactory: controllerFactory,
            startupCheckScheduler: { action in action() }
        )
    }

    private func makePaths() -> AppPaths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AppUpdateManagerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        return AppPaths(root: root)
    }
}

@MainActor
private final class FakeAppUpdateController: AppUpdateControlling {
    private let updaterImplementation = FakeAppUpdateChecking()
    let observation = FakeAppUpdateObservation()

    private var onCanCheckChange: (@MainActor (Bool) -> Void)?
    private(set) var manualCheckCount = 0
    var updater: any AppUpdateChecking {
        updaterImplementation
    }

    var backgroundCheckCount: Int {
        updaterImplementation.backgroundCheckCount
    }

    func checkForUpdates() {
        manualCheckCount += 1
    }

    func observeCanCheckForUpdates(_ handler: @escaping @MainActor (Bool) -> Void) -> any AppUpdateObservation {
        onCanCheckChange = handler
        handler(updater.canCheckForUpdates)
        return observation
    }

    func sendCanCheckUpdate(_ canCheck: Bool) {
        updaterImplementation.canCheckForUpdates = canCheck
        onCanCheckChange?(canCheck)
    }
}

@MainActor
private final class FakeAppUpdateChecking: AppUpdateChecking {
    var canCheckForUpdates = true
    private(set) var backgroundCheckCount = 0

    func checkForUpdatesInBackground() {
        backgroundCheckCount += 1
    }
}

@MainActor
private final class FakeAppUpdateObservation: AppUpdateObservation {
    private(set) var invalidated = false

    func invalidate() {
        invalidated = true
    }
}

private final class ManagerTestWorkloadMonitor: AppUpdateWorkloadMonitoring {
    func currentState() throws -> AppUpdateWorkloadState {
        .idle
    }
}

private final class ManagerTestLogger: AppUpdateLogging {
    func log(_ message: String) {}
}
