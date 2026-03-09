import AppKit
import SwiftUI

@MainActor
final class AppPresentationController {
    static let shared = AppPresentationController()

    private var observerTokens: [ObjectIdentifier: [NSObjectProtocol]] = [:]

    func applicationDidFinishLaunching() {
        NSApp.setActivationPolicy(.accessory)
    }

    func uiWindowWillOpen() {
        NSApp.setActivationPolicy(.regular)
    }

    func presentWindow(_ window: NSWindow?) {
        guard let window else { return }
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func presentWindow(identifier: NSUserInterfaceItemIdentifier) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.presentWindow(AppWindowRegistry.existingWindow(identifier: identifier))
        }
    }

    func registerWindow(_ window: NSWindow, identifier: NSUserInterfaceItemIdentifier) {
        let windowID = ObjectIdentifier(window)
        if observerTokens[windowID] == nil {
            observerTokens[windowID] = makeObservers(for: window)
        }
        AppWindowRegistry.registerWindow(window, identifier: identifier)
        updateActivationPolicy()
    }

    private func makeObservers(for window: NSWindow) -> [NSObjectProtocol] {
        let notificationCenter = NotificationCenter.default
        let names: [NSNotification.Name] = [
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didResignKeyNotification
        ]

        var tokens = names.map { name in
            notificationCenter.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.updateActivationPolicy()
            }
        }

        let closeToken = notificationCenter.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            AppWindowRegistry.unregisterWindow(window)
            self?.observerTokens.removeValue(forKey: ObjectIdentifier(window))
            DispatchQueue.main.async {
                self?.updateActivationPolicy()
            }
        }
        tokens.append(closeToken)

        return tokens
    }

    private func updateActivationPolicy() {
        let shouldShowDock = AppWindowRegistry.existingTrackedWindow().map { window in
            window.isVisible && !window.isMiniaturized
        } ?? false

        let targetPolicy: NSApplication.ActivationPolicy = shouldShowDock ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
        }
    }
}

enum AppWindowRegistry {
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("main-window")
    static let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("settings-window")

    private static weak var mainWindow: NSWindow?
    private static weak var settingsWindow: NSWindow?

    static func registerWindow(_ window: NSWindow, identifier: NSUserInterfaceItemIdentifier) {
        window.identifier = identifier
        switch identifier {
        case mainWindowIdentifier:
            mainWindow = window
        case settingsWindowIdentifier:
            settingsWindow = window
        default:
            break
        }
    }

    static func unregisterWindow(_ window: NSWindow) {
        if mainWindow === window {
            mainWindow = nil
        }
        if settingsWindow === window {
            settingsWindow = nil
        }
    }

    static func existingMainWindow() -> NSWindow? {
        existingWindow(identifier: mainWindowIdentifier)
    }

    static func existingSettingsWindow() -> NSWindow? {
        existingWindow(identifier: settingsWindowIdentifier)
    }

    static func existingTrackedWindow() -> NSWindow? {
        existingMainWindow() ?? existingSettingsWindow()
    }

    static func existingWindow(identifier: NSUserInterfaceItemIdentifier) -> NSWindow? {
        switch identifier {
        case mainWindowIdentifier:
            if let mainWindow, mainWindow.isVisible || mainWindow.isMiniaturized {
                return mainWindow
            }
            mainWindow = nil
        case settingsWindowIdentifier:
            if let settingsWindow, settingsWindow.isVisible || settingsWindow.isMiniaturized {
                return settingsWindow
            }
            settingsWindow = nil
        default:
            break
        }

        let discoveredWindow = NSApp.windows.first {
            $0.identifier == identifier && ($0.isVisible || $0.isMiniaturized)
        }

        switch identifier {
        case mainWindowIdentifier:
            mainWindow = discoveredWindow
        case settingsWindowIdentifier:
            settingsWindow = discoveredWindow
        default:
            break
        }

        return discoveredWindow
    }
}

struct WindowVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
    }
}

struct WindowChromeConfigurator: NSViewRepresentable {
    let windowIdentifier: NSUserInterfaceItemIdentifier
    var style: Style = .immersive

    enum Style {
        case immersive
        case settings
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }
        AppPresentationController.shared.registerWindow(window, identifier: windowIdentifier)
        window.titleVisibility = .hidden
        window.hasShadow = true

        switch style {
        case .immersive:
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            window.toolbarStyle = .unifiedCompact
        case .settings:
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            window.toolbarStyle = .unified
        }
    }
}
