import Foundation
import Testing
@testable import AgentHubBuildServer

struct CodexBundleInjectorTests {
    @Test
    func injectsBinaryIntoTopLevelResourcesCodexPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBundleInjectorTests-\(UUID().uuidString)", isDirectory: true)
        let appBundleURL = root.appendingPathComponent("AgentHub.app", isDirectory: true)
        let sourceBinaryURL = root.appendingPathComponent("codex-universal", isDirectory: false)
        try makeBundleSkeleton(at: appBundleURL)
        try makeExecutable(at: sourceBinaryURL, contents: "#!/bin/sh\necho new\n")

        let injector = CodexBundleInjector()
        let result = try injector.inject(
            universalBinaryURL: sourceBinaryURL,
            intoAppBundle: appBundleURL
        )

        #expect(result.injectedBinaryURL.path == appBundleURL.path + "/Contents/Resources/codex")
        #expect(FileManager.default.isExecutableFile(atPath: result.injectedBinaryURL.path))
    }

    @Test
    func replacesExistingBundledBinary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBundleInjectorTests-\(UUID().uuidString)", isDirectory: true)
        let appBundleURL = root.appendingPathComponent("AgentHub.app", isDirectory: true)
        let resourcesURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let existingBinaryURL = resourcesURL.appendingPathComponent("codex", isDirectory: false)
        let replacementBinaryURL = root.appendingPathComponent("replacement-codex", isDirectory: false)
        try makeBundleSkeleton(at: appBundleURL)
        try makeExecutable(at: existingBinaryURL, contents: "#!/bin/sh\necho old\n")
        try makeExecutable(at: replacementBinaryURL, contents: "#!/bin/sh\necho replacement\n")

        _ = try CodexBundleInjector().inject(
            universalBinaryURL: replacementBinaryURL,
            intoAppBundle: appBundleURL
        )

        let replacedContents = try String(contentsOf: existingBinaryURL, encoding: .utf8)
        #expect(replacedContents.contains("replacement"))
    }
}

private func makeBundleSkeleton(at appBundleURL: URL) throws {
    try FileManager.default.createDirectory(
        at: appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true),
        withIntermediateDirectories: true
    )
}

private func makeExecutable(at url: URL, contents: String) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}
