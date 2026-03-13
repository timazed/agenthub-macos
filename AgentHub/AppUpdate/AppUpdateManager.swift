import Combine
import Foundation
import Sparkle

@MainActor
protocol AppUpdateObservation {
    func invalidate()
}

@MainActor
protocol AppUpdateControlling: AnyObject {
    var updater: AppUpdateChecking { get }
    func checkForUpdates()
    func observeCanCheckForUpdates(_ handler: @escaping @MainActor (Bool) -> Void) -> any AppUpdateObservation
}

@MainActor
final class AppUpdateManager: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isConfigured = false
    @Published private(set) var phase: AppUpdatePhase = .idle

    private let bundle: Bundle
    private let configurationValidator: (Bundle) -> Bool
    private let controllerFactory: (SPUUpdaterDelegate) -> any AppUpdateControlling
    private let startupCheckScheduler: (@escaping @MainActor () -> Void) -> Void
    private var updaterController: (any AppUpdateControlling)?
    private var observation: (any AppUpdateObservation)?
    private let appUpdateTask: AppUpdateTask
    private var hasStarted = false

    init(
        bundle: Bundle,
        paths: AppPaths,
        taskStore: TaskStore,
        activityLogStore: ActivityLogStore,
        appUpdateTask: AppUpdateTask? = nil,
        configurationValidator: ((Bundle) -> Bool)? = nil,
        controllerFactory: ((SPUUpdaterDelegate) -> any AppUpdateControlling)? = nil,
        startupCheckScheduler: ((@escaping @MainActor () -> Void) -> Void)? = nil
    ) {
        self.bundle = bundle
        self.configurationValidator = configurationValidator ?? { SparkleConfiguration(bundle: $0) != nil }
        self.controllerFactory = controllerFactory ?? { SparkleAppUpdateController(updaterDelegate: $0) }
        self.startupCheckScheduler = startupCheckScheduler ?? { action in
            DispatchQueue.main.async {
                Task { @MainActor in
                    action()
                }
            }
        }
        self.appUpdateTask = appUpdateTask ?? AppUpdateTask(
            workloadMonitor: AppUpdateWorkloadMonitor(taskStore: taskStore),
            logger: AppUpdateLogger(paths: paths, activityLogStore: activityLogStore)
        )
        super.init()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        guard configurationValidator(bundle) else {
            canCheckForUpdates = false
            isConfigured = false
            return
        }

        let controller = controllerFactory(self)
        updaterController = controller
        isConfigured = true
        canCheckForUpdates = controller.updater.canCheckForUpdates
        observation = controller.observeCanCheckForUpdates { [weak self] canCheckForUpdates in
            self?.canCheckForUpdates = canCheckForUpdates
        }

        startupCheckScheduler { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.appUpdateTask.performStartupCheck(using: controller.updater)
            self.phase = self.appUpdateTask.phase
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        updaterController = nil
        hasStarted = false
    }

    func checkForUpdates() {
        guard let updaterController else { return }
        appUpdateTask.recordManualCheck()
        phase = appUpdateTask.phase
        updaterController.checkForUpdates()
    }
}

@MainActor
extension AppUpdateManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        appUpdateTask.recordScheduledCheck(delay: delay)
        phase = appUpdateTask.phase
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        appUpdateTask.recordDidFindUpdate(item)
        phase = appUpdateTask.phase
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        appUpdateTask.recordDidNotFindUpdate(error: nil)
        phase = appUpdateTask.phase
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        appUpdateTask.recordDidNotFindUpdate(error: error)
        phase = appUpdateTask.phase
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        appUpdateTask.recordDidDownloadUpdate(item)
        phase = appUpdateTask.phase
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        appUpdateTask.recordDidExtractUpdate(item)
        phase = appUpdateTask.phase
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        appUpdateTask.recordWillInstallUpdate(item)
        phase = appUpdateTask.phase
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        let deferred = appUpdateTask.shouldDeferRelaunch(for: item, installHandler: installHandler)
        phase = appUpdateTask.phase
        return deferred
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        let deferred = appUpdateTask.shouldDeferInstallOnQuit(for: item, installHandler: immediateInstallHandler)
        phase = appUpdateTask.phase
        return deferred
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        appUpdateTask.recordDidAbort(error: error)
        phase = appUpdateTask.phase
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        appUpdateTask.recordUpdateCycleFinished(updateCheck: updateCheck, error: error)
        phase = appUpdateTask.phase
    }
}

private struct SparkleConfiguration {
    let feedURL: URL
    let publicKey: String

    init?(bundle: Bundle) {
        guard let rawFeedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: rawFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              feedURL.scheme?.isEmpty == false else {
            return nil
        }

        guard let rawPublicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return nil
        }

        let publicKey = rawPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !publicKey.isEmpty,
              publicKey != "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY" else {
            return nil
        }

        self.feedURL = feedURL
        self.publicKey = publicKey
    }
}

@MainActor
private final class SparkleAppUpdateObservation: AppUpdateObservation {
    private var observation: NSKeyValueObservation?

    init(observation: NSKeyValueObservation) {
        self.observation = observation
    }

    func invalidate() {
        observation?.invalidate()
        observation = nil
    }
}

@MainActor
private final class SparkleUpdaterAdapter: AppUpdateChecking {
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }

    func checkForUpdatesInBackground() {
        updater.checkForUpdatesInBackground()
    }
}

@MainActor
private final class SparkleAppUpdateController: AppUpdateControlling {
    private let controller: SPUStandardUpdaterController
    private let updaterAdapter: SparkleUpdaterAdapter

    init(updaterDelegate: SPUUpdaterDelegate) {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
        self.controller = controller
        self.updaterAdapter = SparkleUpdaterAdapter(updater: controller.updater)
    }

    var updater: AppUpdateChecking {
        updaterAdapter
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func observeCanCheckForUpdates(_ handler: @escaping @MainActor (Bool) -> Void) -> any AppUpdateObservation {
        let observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { updater, _ in
            Task { @MainActor in
                handler(updater.canCheckForUpdates)
            }
        }
        return SparkleAppUpdateObservation(observation: observation)
    }
}
