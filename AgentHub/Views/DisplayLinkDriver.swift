//
//  DisplayLinkDriver.swift
//  AgentHub
//
//  Created by Timothy Zelinsky on 13/3/2026.
//

import AppKit
import QuartzCore

protocol DisplayLinkDriver: AnyObject {
    var onTick: ((CFTimeInterval) -> Void)? { get set }
    var isRunning: Bool { get }
    func setAnchorView(_ view: NSView?)
    func start()
    func stop()
    func invalidate()
}

final class ViewDisplayLinkDriver: NSObject, DisplayLinkDriver {
    var onTick: ((CFTimeInterval) -> Void)?

    private weak var anchorView: NSView?
    private var displayLink: CADisplayLink?

    var isRunning: Bool {
        displayLink != nil
    }

    func setAnchorView(_ view: NSView?) {
        guard anchorView !== view else { return }
        anchorView = view

        guard isRunning else { return }
        stop()
        start()
    }

    func start() {
        guard displayLink == nil, let anchorView else { return }

        let link = anchorView.displayLink(
            target: self,
            selector: #selector(handleDisplayLinkTick(_:))
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func invalidate() {
        stop()
        anchorView = nil
        onTick = nil
    }

    @objc
    private func handleDisplayLinkTick(_ displayLink: CADisplayLink) {
        onTick?(displayLink.timestamp)
    }
}
