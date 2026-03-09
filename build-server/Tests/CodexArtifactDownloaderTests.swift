import CryptoKit
import Foundation
import Testing
@testable import AgentHubBuildServer

struct CodexArtifactDownloaderTests {
    @Test
    func preparesReleaseByVerifyingChecksumsAndLocatingExtractedBinaries() throws {
        let arm64Archive = Data("arm64-archive".utf8)
        let x64Archive = Data("x64-archive".utf8)
        let checksums = """
        \(sha256Hex(for: arm64Archive))  codex-darwin-arm64.tar.gz
        \(sha256Hex(for: x64Archive))  codex-darwin-x86_64.tar.gz
        """

        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexArtifactDownloaderTests-\(UUID().uuidString)", isDirectory: true)
        let downloader = CodexArtifactDownloader(
            workingDirectoryProvider: { workingDirectory },
            dataProvider: { request in
                switch request.url?.lastPathComponent {
                case "checksums.txt":
                    return Data(checksums.utf8)
                case "codex-darwin-arm64.tar.gz":
                    return arm64Archive
                case "codex-darwin-x86_64.tar.gz":
                    return x64Archive
                default:
                    throw DownloaderFixtureError.unexpectedURL
                }
            },
            archiveExtractor: { archiveURL, destinationURL in
                try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                let binaryURL = destinationURL.appendingPathComponent("codex")
                try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binaryURL, options: [.atomic])
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
                if archiveURL.lastPathComponent.contains("arm64") {
                    #expect(destinationURL.path.contains("/arm64"))
                } else {
                    #expect(destinationURL.path.contains("/x64"))
                }
            }
        )

        let artifacts = try downloader.prepareRelease(
            CodexArtifactDescriptor(
                version: "1.2.3",
                releaseTag: "v1.2.3",
                assets: [
                    CodexReleaseAssetDescriptor(
                        name: "codex-darwin-arm64.tar.gz",
                        downloadURL: URL(string: "https://example.com/codex-darwin-arm64.tar.gz")!,
                        kind: .darwinArm64
                    ),
                    CodexReleaseAssetDescriptor(
                        name: "codex-darwin-x86_64.tar.gz",
                        downloadURL: URL(string: "https://example.com/codex-darwin-x86_64.tar.gz")!,
                        kind: .darwinX64
                    ),
                    CodexReleaseAssetDescriptor(
                        name: "checksums.txt",
                        downloadURL: URL(string: "https://example.com/checksums.txt")!,
                        kind: .checksums
                    ),
                ]
            )
        )

        #expect(artifacts.checksumFileURL.lastPathComponent == "checksums.txt")
        #expect(FileManager.default.isExecutableFile(atPath: artifacts.arm64BinaryURL.path))
        #expect(FileManager.default.isExecutableFile(atPath: artifacts.x64BinaryURL.path))
    }

    @Test
    func failsWhenChecksumDoesNotMatchArchive() throws {
        let downloader = CodexArtifactDownloader(
            workingDirectoryProvider: {
                FileManager.default.temporaryDirectory
                    .appendingPathComponent("CodexArtifactDownloaderTests-\(UUID().uuidString)", isDirectory: true)
            },
            dataProvider: { request in
                switch request.url?.lastPathComponent {
                case "checksums.txt":
                    return Data("0000000000000000000000000000000000000000000000000000000000000000  codex-darwin-arm64.tar.gz\nffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff  codex-darwin-x86_64.tar.gz\n".utf8)
                default:
                    return Data("archive".utf8)
                }
            },
            archiveExtractor: { _, _ in }
        )

        #expect(throws: CodexArtifactDownloaderError.self) {
            try downloader.prepareRelease(
                CodexArtifactDescriptor(
                    version: "1.2.3",
                    releaseTag: "v1.2.3",
                    assets: [
                        CodexReleaseAssetDescriptor(
                            name: "codex-darwin-arm64.tar.gz",
                            downloadURL: URL(string: "https://example.com/codex-darwin-arm64.tar.gz")!,
                            kind: .darwinArm64
                        ),
                        CodexReleaseAssetDescriptor(
                            name: "codex-darwin-x86_64.tar.gz",
                            downloadURL: URL(string: "https://example.com/codex-darwin-x86_64.tar.gz")!,
                            kind: .darwinX64
                        ),
                        CodexReleaseAssetDescriptor(
                            name: "checksums.txt",
                            downloadURL: URL(string: "https://example.com/checksums.txt")!,
                            kind: .checksums
                        ),
                    ]
                )
            )
        }
    }
}

private enum DownloaderFixtureError: Error {
    case unexpectedURL
}

private func sha256Hex(for data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
