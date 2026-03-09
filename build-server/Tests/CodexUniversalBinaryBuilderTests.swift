import Foundation
import Testing
@testable import AgentHubBuildServer

struct CodexUniversalBinaryBuilderTests {
    @Test
    func buildsUniversalBinaryAtExpectedOutputPath() throws {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUniversalBinaryBuilderTests-\(UUID().uuidString)", isDirectory: true)
        let arm64BinaryURL = workingDirectory.appendingPathComponent("arm64/codex")
        let x64BinaryURL = workingDirectory.appendingPathComponent("x64/codex")
        try makeExecutable(at: arm64BinaryURL)
        try makeExecutable(at: x64BinaryURL)

        let builder = CodexUniversalBinaryBuilder(
            processRunner: { _, arguments in
                guard let outputIndex = arguments.firstIndex(of: "-output"),
                      arguments.indices.contains(outputIndex + 1) else {
                    throw BuilderFixtureError.missingOutput
                }

                let outputURL = URL(fileURLWithPath: arguments[outputIndex + 1])
                try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("#!/bin/sh\nexit 0\n".utf8).write(to: outputURL, options: [.atomic])
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outputURL.path)
            }
        )

        let preparedArtifacts = try builder.buildUniversalBinary(
            from: CodexExtractedArtifacts(
                workingDirectory: workingDirectory,
                checksumFileURL: workingDirectory.appendingPathComponent("checksums.txt"),
                arm64BinaryURL: arm64BinaryURL,
                x64BinaryURL: x64BinaryURL
            )
        )

        #expect(preparedArtifacts.universalBinaryURL.path.hasSuffix("/universal/codex"))
        #expect(FileManager.default.isExecutableFile(atPath: preparedArtifacts.universalBinaryURL.path))
    }
}

private enum BuilderFixtureError: Error {
    case missingOutput
}

private func makeExecutable(at url: URL) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url, options: [.atomic])
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}
