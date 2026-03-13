//
//  WindowBackedHeaderBackdropHost.swift
//  AgentHub
//
//  Created by Timothy Zelinsky on 12/3/2026.
//

import SwiftUI
import AppKit

struct WindowBackedHeaderBackdropHost: NSViewRepresentable {
    let bridge: SnapshotSourceBridge
    let width: CGFloat
    let headerHeight: CGFloat
    let isLiveCaptureEnabled: Bool

    func makeNSView(context: Context) -> RootView {
        RootView(bridge: bridge)
    }

    func updateNSView(_ nsView: RootView, context: Context) {
        nsView.update(
            width: width,
            headerHeight: headerHeight,
            isLiveCaptureEnabled: isLiveCaptureEnabled
        )
    }

    static func dismantleNSView(_ nsView: RootView, coordinator: ()) {
        nsView.teardown()
    }

    final class RootView: NSView {
        private let backdropView = HeaderSnapshotSurfaceNSView()
        private let bridge: SnapshotSourceBridge

        private var isLiveCaptureEnabled = true

        override var isFlipped: Bool { true }

        init(bridge: SnapshotSourceBridge) {
            self.bridge = bridge
            super.init(frame: .zero)

            wantsLayer = true
            layer?.masksToBounds = false

            backdropView.translatesAutoresizingMaskIntoConstraints = true
            addSubview(backdropView)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            backdropView.frame = CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: bounds.height
            )

            backdropView.update(
                sourceView: bridge.sourceView,
                configuration: .init(
                    targetSize: bounds.size,
                    isLiveCaptureEnabled: isLiveCaptureEnabled,
                    maxFPS: 120,
                    blurRadius: 20,
                    blurStartPoint: 0.0,
                    blurEndPoint: 1.0
                )
            )
        }

        func update(
            width: CGFloat,
            headerHeight: CGFloat,
            isLiveCaptureEnabled: Bool
        ) {
            let size = CGSize(width: width, height: headerHeight)
            self.frame.size = size
            self.backdropView.frame = CGRect(origin: .zero, size: size)
            self.isLiveCaptureEnabled = isLiveCaptureEnabled
            needsLayout = true
        }

        func teardown() {
            backdropView.teardown()
        }
    }
}
