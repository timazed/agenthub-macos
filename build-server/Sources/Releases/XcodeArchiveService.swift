import Foundation

struct XcodeBuildRequest: Equatable, Sendable {
    var repositoryRootURL: URL
    var projectPath: String
    var scheme: String
    var configuration: String
    var derivedDataURL: URL
}

struct XcodeBuildResult: Equatable, Sendable {
    var appBundleURL: URL
    var derivedDataURL: URL
}

enum XcodeArchiveServiceError: LocalizedError {
    case invalidConfiguration(String)
    case buildFailed(String)
    case productMissing(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return message
        case let .buildFailed(message):
            return message
        case let .productMissing(message):
            return message
        }
    }
}

struct XcodeArchiveService {
    var fileManager: FileManager = .default
    var requestProvider: @Sendable () throws -> XcodeBuildRequest = {
        let repositoryRootURL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )

        return XcodeBuildRequest(
            repositoryRootURL: repositoryRootURL,
            projectPath: "AgentHub.xcodeproj",
            scheme: "AgentHub",
            configuration: "Release",
            derivedDataURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("AgentHubReleaseBuild-\(UUID().uuidString)", isDirectory: true)
        )
    }
    var buildProvider: (@Sendable (XcodeBuildRequest) throws -> XcodeBuildResult)?
    var processRunner: @Sendable (_ executableURL: URL, _ arguments: [String], _ workingDirectoryURL: URL) throws -> Void = {
        executableURL, arguments, workingDirectoryURL in
        try XcodeArchiveService.runProcess(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectoryURL: workingDirectoryURL
        )
    }

    func buildUnsignedApp() throws -> XcodeBuildResult {
        let request = try requestProvider()
        if let buildProvider {
            return try buildProvider(request)
        }

        let projectURL = request.repositoryRootURL.appendingPathComponent(request.projectPath)
        guard fileManager.fileExists(atPath: projectURL.path) else {
            throw XcodeArchiveServiceError.invalidConfiguration(
                "Xcode project not found at \(projectURL.path)"
            )
        }

        try fileManager.createDirectory(at: request.derivedDataURL, withIntermediateDirectories: true)
        try processRunner(
            URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            [
                "-project", request.projectPath,
                "-scheme", request.scheme,
                "-configuration", request.configuration,
                "-derivedDataPath", request.derivedDataURL.path,
                "CODE_SIGNING_ALLOWED=NO",
                "build",
            ],
            request.repositoryRootURL
        )

        let appBundleURL = request.derivedDataURL
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent(request.configuration, isDirectory: true)
            .appendingPathComponent("AgentHub.app", isDirectory: true)

        guard fileManager.fileExists(atPath: appBundleURL.path) else {
            throw XcodeArchiveServiceError.productMissing(
                "Expected built app at \(appBundleURL.path)"
            )
        }

        return XcodeBuildResult(
            appBundleURL: appBundleURL,
            derivedDataURL: request.derivedDataURL
        )
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectoryURL

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw XcodeArchiveServiceError.buildFailed(
                "Failed to launch \(executableURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        process.waitUntilExit()
        let errorOutput = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw XcodeArchiveServiceError.buildFailed(
                errorOutput.isEmpty
                    ? "\(executableURL.lastPathComponent) exited with code \(process.terminationStatus)"
                    : errorOutput
            )
        }
    }
}
