import Foundation

struct SparklePublishPlan: Equatable, Sendable {
    var appArchiveName: String
    var appcastPath: String
    var releaseNotesPath: String
    var channel: String
}

struct SparklePublishService {
    func planPublish(agentHubVersion: String, channel: String) -> SparklePublishPlan {
        SparklePublishPlan(
            appArchiveName: "AgentHub-\(agentHubVersion).zip",
            appcastPath: "updates/\(channel)/appcast.xml",
            releaseNotesPath: "updates/\(channel)/release-notes-\(agentHubVersion).html",
            channel: channel
        )
    }
}
