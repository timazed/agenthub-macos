import Foundation

@MainActor
final class AppUpdateBackgroundTask {
    typealias ScheduleTimer = (TimeInterval, @escaping @Sendable (Timer) -> Void) -> Timer

    let interval: TimeInterval
    var handler: (() -> Void)?

    private let scheduleTimer: ScheduleTimer
    private var timer: Timer?

    var isRunning: Bool {
        timer != nil
    }

    init(
        interval: TimeInterval = 60 * 60,
        scheduleTimer: @escaping ScheduleTimer = { interval, block in
            Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: block)
        },
        handler: (() -> Void)? = nil
    ) {
        self.interval = interval
        self.scheduleTimer = scheduleTimer
        self.handler = handler
    }

    func start() {
        guard timer == nil else { return }
        timer = scheduleTimer(interval) { [weak self] _ in
            Task { @MainActor in
                self?.execute()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func execute() {
        handler?()
    }

    deinit {
        timer?.invalidate()
    }
}
