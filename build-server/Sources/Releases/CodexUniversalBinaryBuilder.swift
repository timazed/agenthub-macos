import Foundation

struct PreparedCodexArtifacts: Equatable, Sendable {
    var workingDirectory: URL
    var checksumFileURL: URL
    var arm64BinaryURL: URL
    var x64BinaryURL: URL
    var universalBinaryURL: URL
}

enum CodexUniversalBinaryBuilderError: LocalizedError {
    case buildFailed(String)
    case outputMissing(String)

    var errorDescription: String? {
        switch self {
        case let .buildFailed(message):
            return message
        case let .outputMissing(message):
            return message
        }
    }
}

struct CodexUniversalBinaryBuilder {
    var fileManager: FileManager = .default
    var preparedArtifactsProvider: (@Sendable (CodexExtractedArtifacts) throws -> PreparedCodexArtifacts)?
    var processRunner: @Sendable (_ executableURL: URL, _ arguments: [String]) throws -> Void = { executableURL, arguments in
        try CodexUniversalBinaryBuilder.runProcess(executableURL: executableURL, arguments: arguments)
    }

    func buildUniversalBinary(from extractedArtifacts: CodexExtractedArtifacts) throws -> PreparedCodexArtifacts {
        if let preparedArtifactsProvider {
            return try preparedArtifactsProvider(extractedArtifacts)
        }

        let universalDirectory = extractedArtifacts.workingDirectory.appendingPathComponent("universal", isDirectory: true)
        try fileManager.createDirectory(at: universalDirectory, withIntermediateDirectories: true)

        let outputURL = universalDirectory.appendingPathComponent("codex", isDirectory: false)
        try processRunner(
            URL(fileURLWithPath: "/usr/bin/lipo"),
            [
                "-create",
                "-output", outputURL.path,
                extractedArtifacts.arm64BinaryURL.path,
                extractedArtifacts.x64BinaryURL.path,
            ]
        )

        guard fileManager.isExecutableFile(atPath: outputURL.path) else {
            throw CodexUniversalBinaryBuilderError.outputMissing(
                "Universal Codex binary was not created at \(outputURL.path)"
            )
        }

        return PreparedCodexArtifacts(
            workingDirectory: extractedArtifacts.workingDirectory,
            checksumFileURL: extractedArtifacts.checksumFileURL,
            arm64BinaryURL: extractedArtifacts.arm64BinaryURL,
            x64BinaryURL: extractedArtifacts.x64BinaryURL,
            universalBinaryURL: outputURL
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
            throw CodexUniversalBinaryBuilderError.buildFailed(
                "Failed to launch \(executableURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        process.waitUntilExit()
        let errorOutput = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw CodexUniversalBinaryBuilderError.buildFailed(
                errorOutput.isEmpty
                    ? "\(executableURL.lastPathComponent) exited with code \(process.terminationStatus)"
                    : errorOutput
            )
        }
    }
}
