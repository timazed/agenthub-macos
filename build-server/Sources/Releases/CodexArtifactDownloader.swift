import CryptoKit
import Foundation

struct CodexExtractedArtifacts: Equatable, Sendable {
    var workingDirectory: URL
    var checksumFileURL: URL
    var arm64BinaryURL: URL
    var x64BinaryURL: URL
}

enum CodexArtifactDownloaderError: LocalizedError {
    case missingRequiredAsset(CodexReleaseAssetKind)
    case downloadFailed(String)
    case checksumMissing(String)
    case checksumMismatch(String)
    case extractionFailed(String)
    case binaryNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .missingRequiredAsset(kind):
            return "Missing required Codex asset for \(kind.rawValue)"
        case let .downloadFailed(message):
            return message
        case let .checksumMissing(filename):
            return "No SHA256 checksum found for \(filename)"
        case let .checksumMismatch(filename):
            return "SHA256 checksum mismatch for \(filename)"
        case let .extractionFailed(message):
            return message
        case let .binaryNotFound(message):
            return message
        }
    }
}

struct CodexArtifactDownloader {
    var fileManager: FileManager = .default
    var preparedReleaseProvider: (@Sendable (CodexArtifactDescriptor) throws -> CodexExtractedArtifacts)?
    var workingDirectoryProvider: @Sendable () -> URL = {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("agenthub-codex-\(UUID().uuidString)", isDirectory: true)
    }
    var dataProvider: @Sendable (URLRequest) throws -> Data = { request in
        try URLSession.shared.codexSynchronousArtifactData(for: request)
    }
    var archiveExtractor: @Sendable (URL, URL) throws -> Void = { archiveURL, destinationURL in
        try CodexArtifactDownloader.extractArchive(at: archiveURL, to: destinationURL)
    }

    func prepareRelease(_ release: CodexArtifactDescriptor) throws -> CodexExtractedArtifacts {
        if let preparedReleaseProvider {
            return try preparedReleaseProvider(release)
        }

        guard let arm64Asset = release.assets.first(where: { $0.kind == .darwinArm64 }) else {
            throw CodexArtifactDownloaderError.missingRequiredAsset(.darwinArm64)
        }
        guard let x64Asset = release.assets.first(where: { $0.kind == .darwinX64 }) else {
            throw CodexArtifactDownloaderError.missingRequiredAsset(.darwinX64)
        }
        let workingDirectory = workingDirectoryProvider()
        let downloadsDirectory = workingDirectory.appendingPathComponent("downloads", isDirectory: true)
        let extractsDirectory = workingDirectory.appendingPathComponent("extracts", isDirectory: true)
        try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: extractsDirectory, withIntermediateDirectories: true)

        let checksumInfo = try prepareChecksums(
            for: release,
            downloadsDirectory: downloadsDirectory,
            requiredAssets: [arm64Asset, x64Asset]
        )

        let arm64ArchiveURL = downloadsDirectory.appendingPathComponent(arm64Asset.name)
        let x64ArchiveURL = downloadsDirectory.appendingPathComponent(x64Asset.name)
        try downloadVerified(asset: arm64Asset, to: arm64ArchiveURL, checksums: checksumInfo.map)
        try downloadVerified(asset: x64Asset, to: x64ArchiveURL, checksums: checksumInfo.map)

        let arm64ExtractDirectory = extractsDirectory.appendingPathComponent("arm64", isDirectory: true)
        let x64ExtractDirectory = extractsDirectory.appendingPathComponent("x64", isDirectory: true)
        try fileManager.createDirectory(at: arm64ExtractDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: x64ExtractDirectory, withIntermediateDirectories: true)

        try archiveExtractor(arm64ArchiveURL, arm64ExtractDirectory)
        try archiveExtractor(x64ArchiveURL, x64ExtractDirectory)

        let arm64BinaryURL = try findCodexBinary(in: arm64ExtractDirectory)
        let x64BinaryURL = try findCodexBinary(in: x64ExtractDirectory)

        return CodexExtractedArtifacts(
            workingDirectory: workingDirectory,
            checksumFileURL: checksumInfo.fileURL,
            arm64BinaryURL: arm64BinaryURL,
            x64BinaryURL: x64BinaryURL
        )
    }

    func parseChecksums(from data: Data) throws -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CodexArtifactDownloaderError.downloadFailed("Checksum file is not valid UTF-8")
        }

        var checksums: [String: String] = [:]
        let simplePattern = try NSRegularExpression(
            pattern: #"^([A-Fa-f0-9]{64})\s+\*?(.+)$"#,
            options: []
        )
        let shasumPattern = try NSRegularExpression(
            pattern: #"^SHA256 \((.+)\) = ([A-Fa-f0-9]{64})$"#,
            options: []
        )

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)

            if let match = simplePattern.firstMatch(in: line, options: [], range: range),
               let checksumRange = Range(match.range(at: 1), in: line),
               let filenameRange = Range(match.range(at: 2), in: line) {
                checksums[String(line[filenameRange])] = String(line[checksumRange]).lowercased()
                continue
            }

            if let match = shasumPattern.firstMatch(in: line, options: [], range: range),
               let filenameRange = Range(match.range(at: 1), in: line),
               let checksumRange = Range(match.range(at: 2), in: line) {
                checksums[String(line[filenameRange])] = String(line[checksumRange]).lowercased()
            }
        }

        return checksums
    }

    private func prepareChecksums(
        for release: CodexArtifactDescriptor,
        downloadsDirectory: URL,
        requiredAssets: [CodexReleaseAssetDescriptor]
    ) throws -> (fileURL: URL, map: [String: String]) {
        if let checksumAsset = release.assets.first(where: { $0.kind == .checksums }) {
            let checksumFileURL = downloadsDirectory.appendingPathComponent(checksumAsset.name)
            let checksumData = try download(asset: checksumAsset)
            try checksumData.write(to: checksumFileURL, options: [.atomic])
            return (checksumFileURL, try parseChecksums(from: checksumData))
        }

        let checksumMap = try checksumMapFromAssetDigests(requiredAssets)
        let checksumFileURL = downloadsDirectory.appendingPathComponent("generated-checksums.txt")
        let checksumText = requiredAssets
            .compactMap { asset in
                checksumMap[asset.name].map { "\($0)  \(asset.name)" }
            }
            .joined(separator: "\n")
            + "\n"
        try Data(checksumText.utf8).write(to: checksumFileURL, options: [.atomic])
        return (checksumFileURL, checksumMap)
    }

    private func checksumMapFromAssetDigests(
        _ assets: [CodexReleaseAssetDescriptor]
    ) throws -> [String: String] {
        var checksumMap: [String: String] = [:]
        for asset in assets {
            guard let digest = normalizedDigest(from: asset.digest) else {
                throw CodexArtifactDownloaderError.missingRequiredAsset(.checksums)
            }
            checksumMap[asset.name] = digest
        }
        return checksumMap
    }

    private func normalizedDigest(from rawDigest: String?) -> String? {
        guard let rawDigest else {
            return nil
        }

        let trimmed = rawDigest.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        let digest: Substring
        if let separatorIndex = trimmed.firstIndex(of: ":") {
            let algorithm = trimmed[..<separatorIndex].lowercased()
            guard algorithm == "sha256" else {
                return nil
            }
            digest = trimmed[trimmed.index(after: separatorIndex)...]
        } else {
            digest = Substring(trimmed)
        }

        let normalized = String(digest).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdef")
        guard normalized.count == 64,
              normalized.unicodeScalars.allSatisfy(hexDigits.contains) else {
            return nil
        }

        return normalized
    }

    private func downloadVerified(
        asset: CodexReleaseAssetDescriptor,
        to destinationURL: URL,
        checksums: [String: String]
    ) throws {
        let data = try download(asset: asset)
        try data.write(to: destinationURL, options: [.atomic])

        guard let expectedChecksum = checksums[asset.name] else {
            throw CodexArtifactDownloaderError.checksumMissing(asset.name)
        }

        let actualChecksum = try sha256(for: destinationURL)
        guard actualChecksum == expectedChecksum else {
            throw CodexArtifactDownloaderError.checksumMismatch(asset.name)
        }
    }

    private func download(asset: CodexReleaseAssetDescriptor) throws -> Data {
        var request = URLRequest(url: asset.downloadURL)
        request.setValue("AgentHubBuildServer/1.0", forHTTPHeaderField: "User-Agent")

        do {
            return try dataProvider(request)
        } catch {
            throw CodexArtifactDownloaderError.downloadFailed(
                "Failed to download \(asset.name): \(error.localizedDescription)"
            )
        }
    }

    private func sha256(for fileURL: URL) throws -> String {
        guard let stream = InputStream(url: fileURL) else {
            throw CodexArtifactDownloaderError.downloadFailed(
                "Unable to open \(fileURL.lastPathComponent) for checksum calculation"
            )
        }

        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            if readCount < 0, let streamError = stream.streamError {
                throw CodexArtifactDownloaderError.downloadFailed(
                    "Failed reading \(fileURL.lastPathComponent): \(streamError.localizedDescription)"
                )
            }
            if readCount == 0 {
                break
            }

            hasher.update(data: Data(bytes: buffer, count: readCount))
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func findCodexBinary(in directory: URL) throws -> URL {
        if fileManager.isExecutableFile(atPath: directory.path),
           directory.lastPathComponent == "codex" {
            return directory
        }

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CodexArtifactDownloaderError.binaryNotFound(
                "Unable to enumerate extracted contents for \(directory.path)"
            )
        }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "codex",
               fileManager.isExecutableFile(atPath: fileURL.path) {
                return fileURL
            }
        }

        throw CodexArtifactDownloaderError.binaryNotFound(
            "Could not locate an executable codex binary in \(directory.path)"
        )
    }

    private static func extractArchive(at archiveURL: URL, to destinationURL: URL) throws {
        let path = archiveURL.path.lowercased()
        if path.hasSuffix(".tar.gz") || path.hasSuffix(".tgz") {
            try runProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-xzf", archiveURL.path, "-C", destinationURL.path]
            )
            return
        }

        if path.hasSuffix(".zip") {
            try runProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
                arguments: ["-o", archiveURL.path, "-d", destinationURL.path]
            )
            return
        }

        let fileManager = FileManager.default
        let candidate = destinationURL.appendingPathComponent("codex")
        if fileManager.isExecutableFile(atPath: archiveURL.path) {
            try fileManager.copyItem(at: archiveURL, to: candidate)
            return
        }

        throw CodexArtifactDownloaderError.extractionFailed(
            "Unsupported Codex artifact format for \(archiveURL.lastPathComponent)"
        )
    }

    private static func runProcess(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw CodexArtifactDownloaderError.extractionFailed(
                "Failed to launch \(executableURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        process.waitUntilExit()
        let errorOutput = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw CodexArtifactDownloaderError.extractionFailed(
                errorOutput.isEmpty
                    ? "\(executableURL.lastPathComponent) exited with code \(process.terminationStatus)"
                    : errorOutput
            )
        }
    }
}

private extension URLSession {
    func codexSynchronousArtifactData(for request: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = LockedArtifactResultBox<Result<Data, Error>>()

        let task = dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                resultBox.store(
                    .failure(
                        CodexArtifactDownloaderError.downloadFailed(error.localizedDescription)
                    )
                )
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                resultBox.store(
                    .failure(
                        CodexArtifactDownloaderError.downloadFailed(
                            "Artifact response was not an HTTP response"
                        )
                    )
                )
                return
            }

            guard (200..<300).contains(httpResponse.statusCode), let data else {
                resultBox.store(
                    .failure(
                        CodexArtifactDownloaderError.downloadFailed(
                            "Artifact request failed with status \(httpResponse.statusCode)"
                        )
                    )
                )
                return
            }

            resultBox.store(.success(data))
        }

        task.resume()
        semaphore.wait()

        return try resultBox.load()?.get() ?? {
            throw CodexArtifactDownloaderError.downloadFailed(
                "Artifact request completed without data"
            )
        }()
    }
}

private final class LockedArtifactResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    func store(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func load() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
