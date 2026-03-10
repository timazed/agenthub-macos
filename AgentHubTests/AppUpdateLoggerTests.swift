import Foundation
import Testing
@testable import AgentHub

struct AppUpdateLoggerTests {
    @Test
    func writesUpdaterLogAndActivityEvent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppUpdateLoggerTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        try paths.prepare()
        let activityLogStore = ActivityLogStore(paths: paths)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let logger = AppUpdateLogger(
            paths: paths,
            activityLogStore: activityLogStore,
            timestampProvider: { fixedDate }
        )

        logger.log("startup_check_requested")

        let logURL = paths.logsDirectory.appendingPathComponent("app-update.log")
        let logContents = try String(contentsOf: logURL)
        let activityEvents = try activityLogStore.load(limit: 10)

        #expect(logContents.contains("[AgentHub][AppUpdate] startup_check_requested"))
        #expect(activityEvents.count == 1)
        #expect(activityEvents.first?.message == "[AppUpdate] startup_check_requested")
    }
}
