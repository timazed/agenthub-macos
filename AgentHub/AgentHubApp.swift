import SwiftUI
import Combine
import AppKit

private enum AppSceneID {
    static let mainWindow = "main-window"
}

private enum AppStatus {
    case starting
    case ready
    case error

    var label: String {
        switch self {
        case .starting:
            return "Starting"
        case .ready:
            return "Ready"
        case .error:
            return "Error"
        }
    }

    var color: Color {
        switch self {
        case .starting:
            return .yellow
        case .ready:
            return .green
        case .error:
            return .red
        }
    }
}

struct AgentHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var bootstrap = AppBootstrap.shared

    var body: some Scene {
        let _ = appDelegate.configureStatusMenu(
            openDashboard: openDashboard,
            openSettings: openSettings
        )

        WindowGroup(id: AppSceneID.mainWindow) {
            Group {
                if let container = bootstrap.container {
                    AppShellView(container: container)
                        .background(.clear)
                } else if let errorMessage = bootstrap.errorMessage {
                    LaunchStateView(
                        title: "Failed to Launch AgentHub",
                        message: errorMessage
                    )
                } else {
                    LaunchStateView(
                        title: "Opening AgentHub",
                        message: "Preparing runtime and local state…"
                    )
                    .task {
                        await bootstrap.loadIfNeeded()
                    }
                }
            }
            .background(WindowChromeConfigurator(
                windowIdentifier: AppWindowRegistry.mainWindowIdentifier,
                style: .immersive
            ))
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Spacer()
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
            .frame(minWidth: 800, minHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 800, height: 800)
        .commands {
            if let appUpdateManager = bootstrap.appUpdateManager {
                AgentHubCommands(appUpdateManager: appUpdateManager)
            }
        }

    }

    private func openDashboard() {
        AppPresentationController.shared.uiWindowWillOpen()
        if let window = AppWindowRegistry.existingMainWindow() {
            AppPresentationController.shared.presentWindow(window)
        } else {
            openWindow(id: AppSceneID.mainWindow)
            AppPresentationController.shared.presentWindow(identifier: AppWindowRegistry.mainWindowIdentifier)
        }
    }

    private func openSettings() {
        AppPresentationController.shared.uiWindowWillOpen()
        if let window = AppWindowRegistry.existingSettingsWindow() {
            AppPresentationController.shared.presentWindow(window)
        } else if let container = bootstrap.container {
            SettingsWindowManager.shared.show(container: container)
        } else if bootstrap.errorMessage == nil {
            Task { @MainActor in
                await bootstrap.loadIfNeeded()
                if let container = bootstrap.container {
                    SettingsWindowManager.shared.show(container: container)
                }
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "Failed to Open Settings"
            alert.informativeText = bootstrap.errorMessage ?? "Unknown error"
            alert.runModal()
        }
    }
}

private struct StatusMenuHostedView: View {
    @StateObject private var bootstrap = AppBootstrap.shared

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(bootstrap.status.color)
                .frame(width: 8, height: 8)
            Text(bootstrap.status.label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .frame(width: 180, alignment: .leading)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusMenuController = StatusMenuController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPresentationController.shared.applicationDidFinishLaunching()
        statusMenuController.installIfNeeded()
        Task { @MainActor in
            await AppBootstrap.shared.loadIfNeeded()
        }
    }

    func configureStatusMenu(
        openDashboard: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void
    ) {
        statusMenuController.installIfNeeded()
        statusMenuController.openDashboard = openDashboard
        statusMenuController.openSettings = openSettings
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
private final class StatusMenuController: NSObject {
    var openDashboard: (() -> Void)?
    var openSettings: (() -> Void)?

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    func installIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "bubble.left.and.bubble.right",
                accessibilityDescription: "AgentHub"
            )
            button.imagePosition = .imageOnly
        }

        let hostedItem = NSMenuItem()
        let hostedView = NSHostingView(rootView: StatusMenuHostedView())
        hostedView.frame = NSRect(x: 0, y: 0, width: 180, height: 28)
        hostedItem.view = hostedView
        menu.addItem(hostedItem)

        menu.addItem(.separator())

        let dashboardItem = NSMenuItem(
            title: "Dashboard",
            action: #selector(handleOpenDashboard),
            keyEquivalent: ""
        )
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(handleOpenSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(handleQuit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func handleOpenDashboard() {
        openDashboard?()
    }

    @objc private func handleOpenSettings() {
        openSettings?()
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }
}

@MainActor
private final class AppBootstrap: ObservableObject {
    static let shared = AppBootstrap()

    @Published var container: AppContainer?
    @Published var appUpdateManager: AppUpdateManager?
    @Published var errorMessage: String?

    private var didStart = false

    var status: AppStatus {
        if errorMessage != nil {
            return .error
        }
        if container != nil {
            return .ready
        }
        return .starting
    }

    func loadIfNeeded() async {
        guard !didStart else { return }
        didStart = true

        let startedAt = Date()
        Self.log("bootstrap_start")

        do {
            let container = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(returning: try AppContainer.makeDefault())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            self.container = container
            let appUpdateManager = AppUpdateManager(
                bundle: .main,
                paths: container.paths,
                taskStore: container.taskStore,
                activityLogStore: container.activityLogStore
            )
            appUpdateManager.start()
            self.appUpdateManager = appUpdateManager
            self.errorMessage = nil
            startBackgroundServices(using: container)
            Self.log("bootstrap_success duration_ms=\(Self.durationMillis(since: startedAt))")
        } catch {
            self.errorMessage = error.localizedDescription
            Self.log("bootstrap_failed duration_ms=\(Self.durationMillis(since: startedAt)) error=\(error.localizedDescription)")
        }
    }

    private func startBackgroundServices(using container: AppContainer) {
        Task.detached(priority: .utility) {
            do {
                try await container.scheduleRunner.reconcileAllAsync(appExecutableURL: container.appExecutableURL)
                await MainActor.run {
                    Self.log("schedule_reconcile_success")
                }
            } catch {
                await MainActor.run {
                    Self.log("schedule_reconcile_failed error=\(error.localizedDescription)")
                }
            }
        }
    }

    private static func durationMillis(since startedAt: Date) -> Int {
        Int(Date().timeIntervalSince(startedAt) * 1000)
    }

    private static func log(_ message: String) {
        let line = "[AgentHub][Startup] \(message)"
        print(line)

        let fileManager = FileManager.default
        let logsDirectory = AppPaths.defaultRoot().appendingPathComponent("logs", isDirectory: true)
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let logURL = logsDirectory.appendingPathComponent("startup.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("[\(timestamp)] \(line)\n".utf8)

        if !fileManager.fileExists(atPath: logURL.path) {
            try? data.write(to: logURL, options: [.atomic])
            return
        }

        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
    }
}

private struct AgentHubCommands: Commands {
    @ObservedObject var appUpdateManager: AppUpdateManager

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                appUpdateManager.checkForUpdates()
            }
            .disabled(!appUpdateManager.canCheckForUpdates)
        }
    }
}

private struct LaunchStateView: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String

    var body: some View {
        let palette = OnboardingPalette.resolve(for: colorScheme)

        OnboardingShell(maxWidth: 760) {
            OnboardingPanel(padding: 30) {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(palette.accent)

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(palette.title)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(palette.body)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 700)
    }
}
