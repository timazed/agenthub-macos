import Foundation
import Testing
@testable import AgentHub

@MainActor
struct AppUpdateBackgroundTaskTests {
    @Test
    func startSchedulesSingleTimerAndStopClearsIt() {
        var scheduledIntervals: [TimeInterval] = []
        let task = AppUpdateBackgroundTask(
            interval: 42,
            scheduleTimer: { interval, _ in
                scheduledIntervals.append(interval)
                return Timer(timeInterval: interval, repeats: true) { _ in }
            }
        )

        task.start()
        task.start()

        #expect(task.isRunning)
        #expect(scheduledIntervals == [42])

        task.stop()

        #expect(!task.isRunning)
    }

    @Test
    func executeInvokesHandler() {
        var fireCount = 0
        let task = AppUpdateBackgroundTask {
            fireCount += 1
        }

        task.execute()

        #expect(fireCount == 1)
    }
}
