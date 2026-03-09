import Foundation
import Testing
@testable import AgentHub

struct CodexBinaryLocatorTests {
    @Test
    func prefersBundledBinaryAtTopLevel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexBinaryLocatorTests-\(UUID().uuidString)", isDirectory: true)
        let resourcesURL = root.appendingPathComponent("Resources", isDirectory: true)
        let binaryURL = resourcesURL.appendingPathComponent("codex", isDirectory: false)
        try makeExecutable(at: binaryURL)

        let locator = CodexBinaryLocator(
            resourceURLProvider: { resourcesURL },
            currentDirectoryURLProvider: { root }
        )

        #expect(try locator.locateBinary().path == binaryURL.path)
    }

    @Test
    func fallsBackToNestedBundledBinary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexBinaryLocatorTests-\(UUID().uuidString)", isDirectory: true)
        let resourcesURL = root.appendingPathComponent("Resources", isDirectory: true)
        let binaryURL = resourcesURL.appendingPathComponent("codex/codex", isDirectory: false)
        try makeExecutable(at: binaryURL)

        let locator = CodexBinaryLocator(
            resourceURLProvider: { resourcesURL },
            currentDirectoryURLProvider: { root }
        )

        #expect(try locator.locateBinary().path == binaryURL.path)
    }

    @Test
    func usesWorkspaceFallbackWhenEnabled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexBinaryLocatorTests-\(UUID().uuidString)", isDirectory: true)
        let binaryURL = root.appendingPathComponent("AgentHub/Resources/codex/codex", isDirectory: false)
        try makeExecutable(at: binaryURL)

        let locator = CodexBinaryLocator(
            resourceURLProvider: { nil },
            currentDirectoryURLProvider: { root }
        )

        #expect(try locator.locateBinary(allowWorkspaceFallback: true).path == binaryURL.path)
    }

    @Test
    func throwsWhenNoExecutableExists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexBinaryLocatorTests-\(UUID().uuidString)", isDirectory: true)
        let locator = CodexBinaryLocator(
            resourceURLProvider: { nil },
            currentDirectoryURLProvider: { root }
        )

        do {
            _ = try locator.locateBinary()
            Issue.record("Expected locateBinary() to throw when no executable exists")
        } catch {
            #expect(error is AssistantRuntimeError)
        }
    }

    private func makeExecutable(at url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
