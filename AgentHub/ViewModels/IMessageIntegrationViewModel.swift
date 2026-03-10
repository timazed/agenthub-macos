import Foundation
import Combine

@MainActor
final class IMessageIntegrationViewModel: ObservableObject {
    @Published private(set) var config: IMessageIntegrationConfig = .default()
    @Published private(set) var permissionStatus: IMessagePermissionStatus
    @Published var draftHandle: String = ""
    @Published var errorMessage: String?

    private let configStore: IMessageIntegrationConfigStore
    private let whitelistService: IMessageWhitelistService
    private let monitorService: IMessageMonitorService
    private let permissionService: IMessagePermissionService

    init(
        configStore: IMessageIntegrationConfigStore,
        whitelistService: IMessageWhitelistService,
        monitorService: IMessageMonitorService,
        permissionService: IMessagePermissionService
    ) {
        self.configStore = configStore
        self.whitelistService = whitelistService
        self.monitorService = monitorService
        self.permissionService = permissionService
        self.permissionStatus = permissionService.currentStatus()
    }

    func load() {
        do {
            config = try configStore.loadOrCreateDefault()
            permissionStatus = permissionService.currentStatus()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setEnabled(_ isEnabled: Bool) {
        var updated = config
        updated.isEnabled = isEnabled
        persist(updated)
    }

    func addHandle() {
        let normalized = whitelistService.normalizeHandle(draftHandle)
        guard !normalized.isEmpty else { return }
        guard !config.allowedHandles.contains(normalized) else {
            draftHandle = ""
            return
        }

        var updated = config
        updated.allowedHandles.append(normalized)
        updated.allowedHandles.sort()
        draftHandle = ""
        persist(updated)
    }

    func removeHandle(_ handle: String) {
        var updated = config
        updated.allowedHandles.removeAll { $0 == handle }
        persist(updated)
    }

    func refreshPermissions() {
        permissionStatus = permissionService.currentStatus()
    }

    func openFullDiskAccessSettings() {
        permissionService.openFullDiskAccessSettings()
    }

    func openAutomationSettings() {
        permissionService.openAutomationSettings()
    }

    func revealAppInFinder() {
        permissionService.revealAppInFinder()
    }

    private func persist(_ updated: IMessageIntegrationConfig) {
        do {
            var next = updated
            next.updatedAt = Date()
            try configStore.save(next)
            config = next
            permissionStatus = permissionService.currentStatus()
            errorMessage = nil
            monitorService.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
