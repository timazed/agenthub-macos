import Foundation
import Darwin

struct AppPaths {
    let root: URL

    var personasDirectory: URL {
        root.appendingPathComponent("personas", isDirectory: true)
    }

    var assistantDirectory: URL {
        root.appendingPathComponent("assistant", isDirectory: true)
    }

    func mainAssistantDirectory(for provider: AuthProvider) -> URL {
        assistantDirectory
            .appendingPathComponent(provider.rawValue, isDirectory: true)
            .appendingPathComponent("main-session", isDirectory: true)
    }

    var tasksDirectory: URL {
        root.appendingPathComponent("tasks", isDirectory: true)
    }

    var logsDirectory: URL {
        root.appendingPathComponent("logs", isDirectory: true)
    }

    var stateDirectory: URL {
        root.appendingPathComponent("state", isDirectory: true)
    }

    var launchAgentsMirrorDirectory: URL {
        stateDirectory.appendingPathComponent("launch-agents", isDirectory: true)
    }

    var runtimeConfigURL: URL {
        stateDirectory.appendingPathComponent("runtime-config.json")
    }

    var legacyAuthStateURL: URL {
        stateDirectory.appendingPathComponent("auth-state.json")
    }

    func authStateURL(for provider: AuthProvider) -> URL {
        stateDirectory.appendingPathComponent("auth-state-\(provider.rawValue).json")
    }

    var legacyCodexAuthStateURL: URL {
        stateDirectory.appendingPathComponent("codex-auth-state.json")
    }

    var historyFileURL: URL {
        root.appendingPathComponent("history.jsonl")
    }

    var runnerLogURL: URL {
        logsDirectory.appendingPathComponent("codex-runner.log")
    }

    var scheduledLogURL: URL {
        logsDirectory.appendingPathComponent("scheduled.log")
    }

    var activityLogURL: URL {
        logsDirectory.appendingPathComponent("activity.ndjson")
    }

    var taskListURL: URL {
        tasksDirectory.appendingPathComponent("tasks.json")
    }

    var taskRunsURL: URL {
        tasksDirectory.appendingPathComponent("runs.ndjson")
    }

    func assistantMetadataURL(for provider: AuthProvider) -> URL {
        mainAssistantDirectory(for: provider).appendingPathComponent("metadata.json")
    }

    func assistantTranscriptURL(for provider: AuthProvider) -> URL {
        mainAssistantDirectory(for: provider).appendingPathComponent("transcript.ndjson")
    }

    static func defaultRoot() -> URL {
        userHomeURL().appendingPathComponent(".agenthub", isDirectory: true)
    }

    static func userHomeURL() -> URL {
        if let pwd = getpwuid(getuid()), let homePointer = pwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homePointer), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    func prepare(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: personasDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: assistantDirectory, withIntermediateDirectories: true)
        for provider in AuthProvider.allCases {
            try fileManager.createDirectory(at: mainAssistantDirectory(for: provider), withIntermediateDirectories: true)
        }
        try fileManager.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: launchAgentsMirrorDirectory, withIntermediateDirectories: true)
    }
}
