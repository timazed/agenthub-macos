import AppKit
import SwiftUI

@MainActor
final class AppPresentationController {
    static let shared = AppPresentationController()

    private var observerTokens: [ObjectIdentifier: [NSObjectProtocol]] = [:]

    func applicationDidFinishLaunching() {
        NSApp.setActivationPolicy(.accessory)
    }

    func dashboardWillOpen() {
        NSApp.setActivationPolicy(.regular)
    }

    func registerMainWindow(_ window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        if observerTokens[windowID] == nil {
            observerTokens[windowID] = makeObservers(for: window)
        }
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
            AppWindowRegistry.unregisterMainWindow(window)
            self?.observerTokens.removeValue(forKey: ObjectIdentifier(window))
            DispatchQueue.main.async {
                self?.updateActivationPolicy()
            }
        }
        tokens.append(closeToken)

        return tokens
    }

    private func updateActivationPolicy() {
        let shouldShowDock = AppWindowRegistry.existingMainWindow().map { window in
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
    private static weak var mainWindow: NSWindow?

    static func registerMainWindow(_ window: NSWindow) {
        window.identifier = mainWindowIdentifier
        mainWindow = window
    }

    static func unregisterMainWindow(_ window: NSWindow) {
        guard mainWindow === window else { return }
        mainWindow = nil
    }

    static func existingMainWindow() -> NSWindow? {
        if let mainWindow, mainWindow.isVisible || mainWindow.isMiniaturized {
            return mainWindow
        }

        mainWindow = nil

        let discoveredWindow = NSApp.windows.first {
            $0.identifier == mainWindowIdentifier && ($0.isVisible || $0.isMiniaturized)
        }
        mainWindow = discoveredWindow
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
        AppWindowRegistry.registerMainWindow(window)
        AppPresentationController.shared.registerMainWindow(window)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.toolbarStyle = .unifiedCompact
        window.styleMask.insert(.fullSizeContentView)
    }
}
