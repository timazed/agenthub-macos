import Foundation
import Sparkle

enum AppUpdatePhase: String, Equatable {
    case idle
    case checking
    case updateAvailable
    case installDeferred
    case installing
}

private enum DeferredInstallKind: String {
    case relaunch
    case installOnQuit
}

@MainActor
final class AppUpdatePolicyCoordinator {
    private struct DeferredInstall {
        var version: String
        var kind: DeferredInstallKind
        var handler: () -> Void
    }

    private let workloadMonitor: AppUpdateWorkloadMonitoring
    private let logger: AppUpdateLogging
    private let pollIntervalNanoseconds: UInt64?

    private var deferredInstall: DeferredInstall?
    private var deferredInstallPollingTask: Task<Void, Never>?
    private(set) var phase: AppUpdatePhase = .idle

    init(
        workloadMonitor: AppUpdateWorkloadMonitoring,
        logger: AppUpdateLogging,
        pollIntervalNanoseconds: UInt64? = 5_000_000_000
    ) {
        self.workloadMonitor = workloadMonitor
        self.logger = logger
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    deinit {
        deferredInstallPollingTask?.cancel()
    }

    func performStartupCheck(using updater: SPUUpdater) {
        guard deferredInstall == nil else {
            logger.log("startup_check_skipped reason=deferred_install_pending")
            return
        }

        phase = .checking
        logger.log("startup_check_requested")
        updater.checkForUpdatesInBackground()
    }

    func recordManualCheck() {
        phase = .checking
        logger.log("manual_check_requested")
    }

    func recordScheduledCheck(delay: TimeInterval) {
        logger.log("scheduled_check delay_seconds=\(Int(delay))")
    }

    func recordUpdateCycleFinished(updateCheck: SPUUpdateCheck, error: Error?) {
        if deferredInstall == nil, phase != .installing {
            phase = .idle
        }

        if let error {
            logger.log("update_cycle_finished check=\(String(describing: updateCheck)) error=\(error.localizedDescription)")
        } else {
            logger.log("update_cycle_finished check=\(String(describing: updateCheck))")
        }
    }

    func recordDidAbort(error: Error) {
        if deferredInstall == nil, phase != .installing {
            phase = .idle
        }
        logger.log("update_cycle_aborted error=\(error.localizedDescription)")
    }

    func recordDidFindUpdate(_ item: SUAppcastItem) {
        phase = .updateAvailable
        logger.log("update_found version=\(item.displayVersionString)")
    }

    func recordDidNotFindUpdate(error: Error?) {
        if deferredInstall == nil, phase != .installing {
            phase = .idle
        }

        if let error {
            logger.log("no_update_found error=\(error.localizedDescription)")
        } else {
            logger.log("no_update_found")
        }
    }

    func recordDidDownloadUpdate(_ item: SUAppcastItem) {
        logger.log("update_downloaded version=\(item.displayVersionString)")
    }

    func recordDidExtractUpdate(_ item: SUAppcastItem) {
        logger.log("update_extracted version=\(item.displayVersionString)")
    }

    func recordWillInstallUpdate(_ item: SUAppcastItem) {
        phase = .installing
        logger.log("update_installing version=\(item.displayVersionString)")
    }

    func shouldDeferRelaunch(for item: SUAppcastItem, installHandler: @escaping () -> Void) -> Bool {
        deferInstallIfNeeded(version: item.displayVersionString, kind: .relaunch, installHandler: installHandler)
    }

    func shouldDeferInstallOnQuit(for item: SUAppcastItem, installHandler: @escaping () -> Void) -> Bool {
        deferInstallIfNeeded(version: item.displayVersionString, kind: .installOnQuit, installHandler: installHandler)
    }

    @discardableResult
    func processDeferredInstallIfIdle() -> Bool {
        guard let deferredInstall else {
            return false
        }

        do {
            let workload = try workloadMonitor.currentState()
            guard !workload.isBusy else {
                logger.log("deferred_install_waiting version=\(deferredInstall.version) reason=\(workload.reason?.rawValue ?? "busy")")
                return false
            }
        } catch {
            logger.log("deferred_install_waiting version=\(deferredInstall.version) reason=monitor_error error=\(error.localizedDescription)")
            return false
        }

        self.deferredInstall = nil
        stopPollingDeferredInstall()
        phase = .installing
        logger.log("deferred_install_resumed version=\(deferredInstall.version) kind=\(deferredInstall.kind.rawValue)")
        deferredInstall.handler()
        return true
    }

    private func deferInstallIfNeeded(
        version: String,
        kind: DeferredInstallKind,
        installHandler: @escaping () -> Void
    ) -> Bool {
        do {
            let workload = try workloadMonitor.currentState()
            guard workload.isBusy else {
                logger.log("install_not_deferred version=\(version) kind=\(kind.rawValue)")
                return false
            }

            deferredInstall = DeferredInstall(version: version, kind: kind, handler: installHandler)
            phase = .installDeferred
            logger.log("install_deferred version=\(version) kind=\(kind.rawValue) reason=\(workload.reason?.rawValue ?? "busy")")
            startPollingDeferredInstallIfNeeded()
            return true
        } catch {
            deferredInstall = DeferredInstall(version: version, kind: kind, handler: installHandler)
            phase = .installDeferred
            logger.log("install_deferred version=\(version) kind=\(kind.rawValue) reason=monitor_error error=\(error.localizedDescription)")
            startPollingDeferredInstallIfNeeded()
            return true
        }
    }

    private func startPollingDeferredInstallIfNeeded() {
        guard deferredInstallPollingTask == nil, let pollIntervalNanoseconds else {
            return
        }

        deferredInstallPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                guard let self else { return }
                if self.processDeferredInstallIfIdle() {
                    return
                }
            }
        }
    }

    private func stopPollingDeferredInstall() {
        deferredInstallPollingTask?.cancel()
        deferredInstallPollingTask = nil
    }
}
