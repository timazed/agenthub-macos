import Foundation
import Testing
@testable import AgentHub

struct BrowserPersistenceTests {
    @Test
    func browserPolicyRegistryCreatesDefaultDocument() throws {
        let paths = makePaths()
        let registry = BrowserPolicyRegistry(paths: paths)

        let document = try registry.loadOrCreateDefault()

        #expect(document.profiles.count == 1)
        #expect(document.profiles.first?.profileId == "default")
        #expect(document.policies.count == 1)
        #expect(document.policies.first?.profileId == "default")
        #expect(FileManager.default.fileExists(atPath: paths.browserRegistryURL.path))
    }

    @Test
    func browserPolicyRegistryPersistsCustomProfilesAndPolicies() throws {
        let paths = makePaths()
        let registry = BrowserPolicyRegistry(paths: paths)
        let document = BrowserRegistryDocument(
            profiles: [
                BrowserProfileRecord(
                    profileId: "opentable",
                    displayName: "OpenTable",
                    notes: "Primary reservation profile",
                    toolingKind: .generic,
                    storageScope: .sharedDefault
                )
            ],
            policies: [
                BrowserPolicyRecord(
                    profileId: "opentable",
                    displayName: "OpenTable",
                    allowedHosts: ["www.opentable.com"],
                    confirmationRules: [BrowserConfirmationRule(actionType: .submit, hostPattern: "www.opentable.com", notes: nil)],
                    notes: nil
                )
            ],
            updatedAt: Date()
        )

        try registry.save(document)

        let loadedProfile = try registry.profile(for: "opentable")
        let loadedPolicy = try registry.policy(for: "opentable")

        #expect(loadedProfile?.displayName == "OpenTable")
        #expect(loadedPolicy?.allowedHosts == ["www.opentable.com"])
    }

    @Test
    func browserActionLogStoreAppendsAndLoadsRecords() throws {
        let paths = makePaths()
        let store = BrowserActionLogStore(paths: paths)
        let sessionId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

        try store.append(
            BrowserActionRecord(
                id: UUID(),
                sessionId: sessionId,
                profileId: "opentable",
                currentURL: "https://www.opentable.com/r/demo",
                actionType: .click,
                target: "Find a Table",
                value: nil,
                result: .succeeded,
                error: nil,
                createdAt: createdAt
            )
        )

        let records = try store.load()

        #expect(records.count == 1)
        #expect(records.first?.sessionId == sessionId)
        #expect(records.first?.actionType == .click)
        #expect(FileManager.default.fileExists(atPath: paths.browserActionLogURL.path))
    }

    @Test
    func browserConfirmationStoreUpsertsRecords() throws {
        let paths = makePaths()
        let store = BrowserConfirmationStore(paths: paths)
        let confirmationId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_100)
        let initial = BrowserConfirmationRecord(
            id: confirmationId,
            sessionId: UUID(),
            profileId: "opentable",
            actionType: .submit,
            target: "Confirm reservation",
            currentURL: "https://www.opentable.com/booking",
            pageTitle: "Complete reservation",
            resolution: .pending,
            createdAt: createdAt,
            resolvedAt: nil
        )

        try store.upsert(initial)
        try store.upsert(
            BrowserConfirmationRecord(
                id: confirmationId,
                sessionId: initial.sessionId,
                profileId: initial.profileId,
                actionType: initial.actionType,
                target: initial.target,
                currentURL: initial.currentURL,
                pageTitle: initial.pageTitle,
                resolution: .approved,
                createdAt: initial.createdAt,
                resolvedAt: createdAt.addingTimeInterval(10)
            )
        )

        let records = try store.load()

        #expect(records.count == 1)
        #expect(records.first?.resolution == .approved)
        #expect(FileManager.default.fileExists(atPath: paths.browserConfirmationsURL.path))
    }

    private func makePaths() -> AppPaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentHubBrowserTests-\(UUID().uuidString)", isDirectory: true)
        return AppPaths(root: root)
    }
}
