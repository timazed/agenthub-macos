import Foundation

struct CodexBundleInjectionResult: Equatable, Sendable {
    var appBundleURL: URL
    var injectedBinaryURL: URL
}

enum CodexBundleInjectorError: LocalizedError {
    case bundleMissing(String)
    case injectionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .bundleMissing(message):
            return message
        case let .injectionFailed(message):
            return message
        }
    }
}

struct CodexBundleInjector {
    var fileManager: FileManager = .default
    var injectionProvider: (@Sendable (URL, URL) throws -> CodexBundleInjectionResult)?

    func inject(
        universalBinaryURL: URL,
        intoAppBundle appBundleURL: URL
    ) throws -> CodexBundleInjectionResult {
        if let injectionProvider {
            return try injectionProvider(universalBinaryURL, appBundleURL)
        }

        guard fileManager.fileExists(atPath: appBundleURL.path) else {
            throw CodexBundleInjectorError.bundleMissing(
                "App bundle does not exist at \(appBundleURL.path)"
            )
        }

        let resourcesDirectory = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)

        let destinationURL = resourcesDirectory.appendingPathComponent("codex", isDirectory: false)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.copyItem(at: universalBinaryURL, to: destinationURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
        } catch {
            throw CodexBundleInjectorError.injectionFailed(
                "Failed to inject Codex binary: \(error.localizedDescription)"
            )
        }

        return CodexBundleInjectionResult(
            appBundleURL: appBundleURL,
            injectedBinaryURL: destinationURL
        )
    }
}
