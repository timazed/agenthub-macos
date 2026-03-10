import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdateManager: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isConfigured = false
    @Published private(set) var phase: AppUpdatePhase = .idle

    private enum CheckSource {
        case manual
        case background
    }

    private let bundle: Bundle
    private var updaterController: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?
    private let appUpdateTask: AppUpdateTask
    private let backgroundTask: AppUpdateBackgroundTask
    private var hasStarted = false

    init(
        bundle: Bundle,
        paths: AppPaths,
        taskStore: TaskStore,
        activityLogStore: ActivityLogStore,
        backgroundTask: AppUpdateBackgroundTask? = nil
    ) {
        self.bundle = bundle
        self.appUpdateTask = AppUpdateTask(
            workloadMonitor: AppUpdateWorkloadMonitor(taskStore: taskStore),
            logger: AppUpdateLogger(paths: paths, activityLogStore: activityLogStore)
        )
        self.backgroundTask = backgroundTask ?? AppUpdateBackgroundTask()
        super.init()
        self.backgroundTask.handler = { [weak self] in
            self?.checkForUpdates(source: .background)
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        guard SparkleConfiguration(bundle: bundle) != nil else {
            canCheckForUpdates = false
            isConfigured = false
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController = controller
        isConfigured = true
        canCheckForUpdates = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            guard let self else { return }
            Task { @MainActor in
                self.canCheckForUpdates = updater.canCheckForUpdates
            }
        }

        DispatchQueue.main.async { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.appUpdateTask.performStartupCheck(using: controller.updater)
            self.phase = self.appUpdateTask.phase
        }

        backgroundTask.start()
    }

    func stop() {
        backgroundTask.stop()
        observation?.invalidate()
        observation = nil
        updaterController = nil
        hasStarted = false
    }

    func checkForUpdates() {
        checkForUpdates(source: .manual)
    }

    private func checkForUpdates(source: CheckSource) {
        guard let updaterController else { return }

        switch source {
        case .manual:
            appUpdateTask.recordManualCheck()
            phase = appUpdateTask.phase
            updaterController.checkForUpdates(nil)
        case .background:
            appUpdateTask.performBackgroundCheck(using: updaterController.updater)
            phase = appUpdateTask.phase
        }
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
