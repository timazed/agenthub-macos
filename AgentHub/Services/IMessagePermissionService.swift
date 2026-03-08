import AppKit
import Carbon
import Foundation

struct IMessagePermissionStatus {
    enum State: Hashable {
        case granted
        case missing
        case unavailable
    }

    var fullDiskAccess: State
    var automation: State
    var appPath: String
}

@MainActor
final class IMessagePermissionService {
    func currentStatus() -> IMessagePermissionStatus {
        IMessagePermissionStatus(
            fullDiskAccess: fullDiskAccessState(),
            automation: automationState(),
            appPath: Bundle.main.bundleURL.path
        )
    }

    func openFullDiskAccessSettings() {
        if let deepLink = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"),
           NSWorkspace.shared.open(deepLink) {
            return
        }

        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.SystemSettings") {
            _ = NSWorkspace.shared.open(settingsURL)
        }
    }

    func openAutomationSettings() {
        if let deepLink = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"),
           NSWorkspace.shared.open(deepLink) {
            return
        }

        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.SystemSettings") {
            _ = NSWorkspace.shared.open(settingsURL)
        }
    }

    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func fullDiskAccessState() -> IMessagePermissionStatus.State {
        let dbURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")

        do {
            let handle = try FileHandle(forReadingFrom: dbURL)
            try handle.close()
            return .granted
        } catch {
            return .missing
        }
    }

    private func automationState() -> IMessagePermissionStatus.State {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.MobileSMS")
        guard let descriptorPointer = target.aeDesc else {
            return .unavailable
        }

        var descriptor = descriptorPointer.pointee
        let status = AEDeterminePermissionToAutomateTarget(
            &descriptor,
            typeWildCard,
            typeWildCard,
            false
        )

        switch status {
        case noErr:
            return .granted
        case -1743, -1744:
            return .missing
        default:
            return .unavailable
        }
    }
}
