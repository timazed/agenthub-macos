import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isConfigured = false
    @Published private(set) var phase: AppUpdatePhase = .idle

    private var updaterController: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?
    private let policyCoordinator: AppUpdatePolicyCoordinator

    init(
        bundle: Bundle,
        paths: AppPaths,
        taskStore: TaskStore,
        activityLogStore: ActivityLogStore
    ) {
        self.policyCoordinator = AppUpdatePolicyCoordinator(
            workloadMonitor: AppUpdateWorkloadMonitor(taskStore: taskStore),
            logger: AppUpdateLogger(paths: paths, activityLogStore: activityLogStore)
        )
        super.init()

        guard SparkleConfiguration(bundle: bundle) != nil else {
            self.canCheckForUpdates = false
            self.isConfigured = false
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
            self.policyCoordinator.performStartupCheck(using: controller.updater)
            self.phase = self.policyCoordinator.phase
        }
    }

    func checkForUpdates() {
        guard let updaterController else { return }
        policyCoordinator.recordManualCheck()
        phase = policyCoordinator.phase
        updaterController.checkForUpdates(nil)
    }
}

@MainActor
extension AppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        policyCoordinator.recordScheduledCheck(delay: delay)
        phase = policyCoordinator.phase
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        policyCoordinator.recordDidFindUpdate(item)
        phase = policyCoordinator.phase
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        policyCoordinator.recordDidNotFindUpdate(error: nil)
        phase = policyCoordinator.phase
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        policyCoordinator.recordDidNotFindUpdate(error: error)
        phase = policyCoordinator.phase
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        policyCoordinator.recordDidDownloadUpdate(item)
        phase = policyCoordinator.phase
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        policyCoordinator.recordDidExtractUpdate(item)
        phase = policyCoordinator.phase
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        policyCoordinator.recordWillInstallUpdate(item)
        phase = policyCoordinator.phase
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        let deferred = policyCoordinator.shouldDeferRelaunch(for: item, installHandler: installHandler)
        phase = policyCoordinator.phase
        return deferred
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        let deferred = policyCoordinator.shouldDeferInstallOnQuit(for: item, installHandler: immediateInstallHandler)
        phase = policyCoordinator.phase
        return deferred
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        policyCoordinator.recordDidAbort(error: error)
        phase = policyCoordinator.phase
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        policyCoordinator.recordUpdateCycleFinished(updateCheck: updateCheck, error: error)
        phase = policyCoordinator.phase
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
