import Foundation

public struct CEFRuntimeConfiguration: Sendable {
    public let cefVersion: String
    public let chromiumVersion: String
    public let runtimeRoot: URL
    public let buildConfiguration: String

    public init(
        cefVersion: String,
        chromiumVersion: String,
        runtimeRoot: URL,
        buildConfiguration: String
    ) {
        self.cefVersion = cefVersion
        self.chromiumVersion = chromiumVersion
        self.runtimeRoot = runtimeRoot
        self.buildConfiguration = buildConfiguration
    }
}

public struct CEFRuntimeResolution: Sendable {
    public let frameworkRoot: URL
    public let frameworkBinary: URL
    public let resourcesRoot: URL
}

public enum CEFBootstrapStatus: Sendable {
    case present(CEFRuntimeResolution)
    case missing(reason: String)
    case error(reason: String)
}

public enum CEFRuntimeLocator {
    public static let defaultCEFVersion = "136.1.4+g89c0a8c+chromium-136.0.7103.93"
    public static let defaultChromiumVersion = "136.0.7103.93"

    public static func defaultConfiguration(
        buildConfiguration: String = "Release",
        repoRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> CEFRuntimeConfiguration {
        let runtimeRoot = repoRoot
            .appendingPathComponent("Vendor", isDirectory: true)
            .appendingPathComponent("CEFRuntime", isDirectory: true)
            .appendingPathComponent(defaultCEFVersion, isDirectory: true)
        return CEFRuntimeConfiguration(
            cefVersion: defaultCEFVersion,
            chromiumVersion: defaultChromiumVersion,
            runtimeRoot: runtimeRoot,
            buildConfiguration: buildConfiguration
        )
    }

    public static func resolve(
        _ configuration: CEFRuntimeConfiguration = CEFRuntimeLocator.defaultConfiguration()
    ) -> CEFBootstrapStatus {
        let fm = FileManager.default
        let frameworkRoot = configuration.runtimeRoot
            .appendingPathComponent(configuration.buildConfiguration, isDirectory: true)
            .appendingPathComponent("Chromium Embedded Framework.framework", isDirectory: true)
        let frameworkBinary = frameworkRoot.appendingPathComponent("Chromium Embedded Framework")
        let resourcesRoot = frameworkRoot.appendingPathComponent("Resources", isDirectory: true)

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: configuration.runtimeRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing(
                reason: "CEF runtime root missing at \(configuration.runtimeRoot.path). Run scripts/bootstrap_cef_runtime.sh."
            )
        }

        guard fm.fileExists(atPath: frameworkRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing(
                reason: "Missing framework at \(frameworkRoot.path). Run scripts/bootstrap_cef_runtime.sh."
            )
        }

        guard fm.fileExists(atPath: frameworkBinary.path) else {
            return .error(reason: "CEF framework binary missing at \(frameworkBinary.path).")
        }

        guard fm.fileExists(atPath: resourcesRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .error(reason: "CEF resources directory missing at \(resourcesRoot.path).")
        }

        return .present(
            CEFRuntimeResolution(
                frameworkRoot: frameworkRoot,
                frameworkBinary: frameworkBinary,
                resourcesRoot: resourcesRoot
            )
        )
    }
}
