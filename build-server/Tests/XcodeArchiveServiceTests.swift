import Foundation
import Testing
@testable import AgentHubBuildServer

struct XcodeArchiveServiceTests {
    @Test
    func returnsBuiltAppBundleFromInjectedBuildProvider() throws {
        let repositoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("XcodeArchiveServiceTests-\(UUID().uuidString)", isDirectory: true)
        let request = XcodeBuildRequest(
            repositoryRootURL: repositoryRoot,
            projectPath: "AgentHub.xcodeproj",
            scheme: "AgentHub",
            configuration: "Release",
            derivedDataURL: repositoryRoot.appendingPathComponent("DerivedData", isDirectory: true)
        )
        let expectedResult = XcodeBuildResult(
            appBundleURL: request.derivedDataURL
                .appendingPathComponent("Build", isDirectory: true)
                .appendingPathComponent("Products", isDirectory: true)
                .appendingPathComponent("Release", isDirectory: true)
                .appendingPathComponent("AgentHub.app", isDirectory: true),
            derivedDataURL: request.derivedDataURL
        )

        let service = XcodeArchiveService(
            requestProvider: { request },
            buildProvider: { providedRequest in
                #expect(providedRequest == request)
                return expectedResult
            }
        )

        let result = try service.buildUnsignedApp()

        #expect(result == expectedResult)
    }

    @Test
    func failsWhenProjectDoesNotExist() throws {
        let repositoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("XcodeArchiveServiceTests-\(UUID().uuidString)", isDirectory: true)
        let service = XcodeArchiveService(
            requestProvider: {
                XcodeBuildRequest(
                    repositoryRootURL: repositoryRoot,
                    projectPath: "Missing.xcodeproj",
                    scheme: "AgentHub",
                    configuration: "Release",
                    derivedDataURL: repositoryRoot.appendingPathComponent("DerivedData", isDirectory: true)
                )
            }
        )

        #expect(throws: XcodeArchiveServiceError.self) {
            try service.buildUnsignedApp()
        }
    }
}
