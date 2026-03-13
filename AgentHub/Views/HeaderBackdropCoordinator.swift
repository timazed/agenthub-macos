//
//  HeaderBackdropCoordinator.swift
//  AgentHub
//
//  Created by Timothy Zelinsky on 13/3/2026.
//

import AppKit
import QuartzCore

final class HeaderBackdropCoordinator {
    struct Configuration: Equatable {
        var targetSize: CGSize = .zero
        var isLiveCaptureEnabled = false
        var maxFPS: Double = 30
        var blurRadius: CGFloat = 20
        var blurStartPoint: CGFloat = 0
        var blurEndPoint: CGFloat = 1
    }

    weak var sourceView: NSView?
    weak var captureView: NSView?

    var onFrameReady: ((CGImage) -> Void)? {
        didSet {
            renderer.onFrameReady = onFrameReady
        }
    }

    private let driver: DisplayLinkDriver
    private let renderer = HeaderBackdropRenderer()

    private var configuration = Configuration()

    private var isCaptureScheduled = false
    private var hasPendingForcedCapture = false
    private var lastCaptureTimestamp: CFTimeInterval = 0
    private var lastCapturedSourceRect: CGRect = .null
    private var requestCounter: UInt64 = 0

    private var applicationObservers: [NSObjectProtocol] = []

    init(driver: DisplayLinkDriver = ViewDisplayLinkDriver()) {
        self.driver = driver

        self.driver.onTick = { [weak self] timestamp in
            self?.handleDisplayLinkTick(timestamp: timestamp)
        }

        observeApplicationLifecycle()
    }

    deinit {
        applicationObservers.forEach(NotificationCenter.default.removeObserver)
        driver.invalidate()
    }

    func updateConfiguration(_ newConfiguration: Configuration) {
        let oldConfiguration = configuration
        configuration = newConfiguration

        renderer.updateConfiguration(
            .init(
                outputSize: newConfiguration.targetSize,
                blurRadius: newConfiguration.blurRadius,
                blurStartPoint: newConfiguration.blurStartPoint,
                blurEndPoint: newConfiguration.blurEndPoint,
                scaleFactor: NSScreen.main?.backingScaleFactor ?? 2
            )
        )

        if oldConfiguration.targetSize != newConfiguration.targetSize {
            requestCapture(force: true)
        }

        if oldConfiguration.isLiveCaptureEnabled != newConfiguration.isLiveCaptureEnabled ||
            oldConfiguration.maxFPS != newConfiguration.maxFPS {
            updateLiveCaptureState()
        }
    }

    func registerSourceView(_ view: NSView) {
        guard sourceView !== view else {
            requestCapture(force: true)
            updateLiveCaptureState()
            return
        }

        sourceView = view
        driver.setAnchorView(view)
        lastCapturedSourceRect = .null

        requestCapture(force: true)
        updateLiveCaptureState()
    }

    func unregisterSourceView() {
        sourceView = nil
        driver.setAnchorView(nil)
        lastCapturedSourceRect = .null
        updateLiveCaptureState()
    }

    func registerCaptureView(_ view: NSView) {
        guard captureView !== view else { return }
        captureView = view
        requestCapture(force: true)
        updateLiveCaptureState()
    }

    func unregisterCaptureView() {
        captureView = nil
        updateLiveCaptureState()
    }

    func captureViewVisibilityDidChange() {
        updateLiveCaptureState()
        requestCapture(force: true)
    }

    func stopLiveCapture() {
        driver.stop()
    }

    func requestCapture(force: Bool = false) {
        hasPendingForcedCapture = hasPendingForcedCapture || force
        guard !isCaptureScheduled else { return }

        isCaptureScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isCaptureScheduled = false

            let pendingForce = self.hasPendingForcedCapture
            self.hasPendingForcedCapture = false

            self.captureIfNeeded(force: pendingForce, timestamp: CACurrentMediaTime())
        }
    }

    private func observeApplicationLifecycle() {
        let center = NotificationCenter.default

        applicationObservers.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.captureViewVisibilityDidChange()
            }
        )

        applicationObservers.append(
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.captureViewVisibilityDidChange()
            }
        )
    }

    private func handleDisplayLinkTick(timestamp: CFTimeInterval) {
        guard configuration.isLiveCaptureEnabled else {
            driver.stop()
            return
        }

        guard shouldCaptureNow else {
            driver.stop()
            return
        }

        captureIfNeeded(force: false, timestamp: timestamp)
    }

    private var minimumCaptureInterval: CFTimeInterval {
        let fps = max(configuration.maxFPS, 1)
        return 1.0 / fps
    }

    private var shouldCaptureNow: Bool {
        guard let sourceView, let captureView else { return false }
        guard captureView.window != nil, sourceView.window != nil else { return false }
        guard captureView.window === sourceView.window else { return false }
        guard configuration.targetSize.width > 1, configuration.targetSize.height > 1 else { return false }
        guard !captureView.isHiddenOrHasHiddenAncestor else { return false }
        guard !sourceView.isHiddenOrHasHiddenAncestor else { return false }
        guard captureView.alphaValue > 0.01, sourceView.alphaValue > 0.01 else { return false }

        if let window = captureView.window {
            guard window.isVisible else { return false }
        }

        return true
    }

    private func updateLiveCaptureState() {
        if configuration.isLiveCaptureEnabled, shouldCaptureNow {
            driver.start()
            requestCapture(force: true)
        } else {
            driver.stop()
        }
    }

    private func captureIfNeeded(force: Bool, timestamp: CFTimeInterval) {
        guard shouldCaptureNow else { return }

        if !force, timestamp - lastCaptureTimestamp < minimumCaptureInterval {
            return
        }

        guard let sourceView, let captureView else { return }

        let captureRectInWindow = captureView.convert(captureView.bounds, to: nil)
        let sourceRect = sourceView
            .convert(captureRectInWindow, from: nil)
            .intersection(sourceView.bounds)

        guard sourceRect.width > 1, sourceRect.height > 1 else { return }

        if !force, sourceRect.equalTo(lastCapturedSourceRect), !configuration.isLiveCaptureEnabled {
            return
        }

        guard let cgImage = captureCGImage(from: sourceView, rect: sourceRect) else {
            return
        }

        lastCaptureTimestamp = timestamp
        lastCapturedSourceRect = sourceRect
        requestCounter &+= 1

        renderer.enqueueRender(
            sourceImage: cgImage,
            sourceRect: CGRect(origin: .zero, size: sourceRect.size),
            requestID: requestCounter
        )
    }

    private func captureCGImage(from sourceView: NSView, rect: CGRect) -> CGImage? {
        let integralRect = rect.integralRect
        guard integralRect.width > 0, integralRect.height > 0 else { return nil }

        guard let bitmap = sourceView.bitmapImageRepForCachingDisplay(in: integralRect) else {
            return nil
        }

        bitmap.size = integralRect.size
        sourceView.cacheDisplay(in: integralRect, to: bitmap)

        return bitmap.cgImage
    }
}

private extension CGRect {
    var integralRect: CGRect {
        CGRect(
            x: floor(origin.x),
            y: floor(origin.y),
            width: ceil(size.width),
            height: ceil(size.height)
        )
    }
}
