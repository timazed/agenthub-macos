//
//  WindowBackedSceneHost.swift
//  AgentHub
//
//  Created by Timothy Zelinsky on 12/3/2026.
//

import SwiftUI
import AppKit
import Combine

final class SnapshotSourceBridge: ObservableObject {
    weak var sourceView: NSView?

    @Published private(set) var topChromeInset: CGFloat = 0

    func updateTopChromeInset(_ value: CGFloat) {
        guard topChromeInset != value else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.topChromeInset != value else { return }
            self.topChromeInset = value
        }
    }
}

struct WindowBackedSceneHost<Scene: View>: NSViewRepresentable {
    let bridge: SnapshotSourceBridge
    let scene: () -> Scene

    init(
        bridge: SnapshotSourceBridge,
        @ViewBuilder scene: @escaping () -> Scene
    ) {
        self.bridge = bridge
        self.scene = scene
    }

    func makeNSView(context: Context) -> RootView {
        RootView(scene: scene(), bridge: bridge)
    }

    func updateNSView(_ nsView: RootView, context: Context) {
        nsView.updateScene(scene())
    }

    static func dismantleNSView(_ nsView: RootView, coordinator: ()) {
        nsView.teardown()
    }

    final class RootView: NSView {
        private let sceneHostingView: NSHostingView<Scene>
        private let bridge: SnapshotSourceBridge

        private weak var resizeObserver: NSObjectProtocol?
        private weak var liveResizeObserver: NSObjectProtocol?

        override var isFlipped: Bool { true }

        init(scene: Scene, bridge: SnapshotSourceBridge) {
            self.sceneHostingView = NSHostingView(rootView: scene)
            self.bridge = bridge
            super.init(frame: .zero)

            wantsLayer = true
            layer?.masksToBounds = false

            sceneHostingView.translatesAutoresizingMaskIntoConstraints = true
            addSubview(sceneHostingView)

            bridge.sourceView = sceneHostingView
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installWindowObserversIfNeeded()
            publishTopInset()
        }

        override func layout() {
            super.layout()

            let inset = bridge.topChromeInset

            sceneHostingView.frame = CGRect(
                x: 0,
                y: -inset,
                width: bounds.width,
                height: bounds.height + inset
            )

            if bridge.sourceView !== sceneHostingView {
                bridge.sourceView = sceneHostingView
            }
        }

        func updateScene(_ scene: Scene) {
            sceneHostingView.rootView = scene
        }

        func teardown() {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
            if let liveResizeObserver {
                NotificationCenter.default.removeObserver(liveResizeObserver)
            }

            if bridge.sourceView === sceneHostingView {
                bridge.sourceView = nil
            }
        }

        private func installWindowObserversIfNeeded() {
            guard let window else { return }
            guard resizeObserver == nil, liveResizeObserver == nil else { return }

            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.publishTopInset()
            }

            liveResizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.publishTopInset()
            }
        }

        private func publishTopInset() {
            guard let window else { return }

            let inset = max(
                window.frame.height - window.contentLayoutRect.height,
                0
            )

            bridge.updateTopChromeInset(inset)
        }
    }
}
