//import SwiftUI
//import AppKit
//import QuartzCore
//import VariableBlurImageView
//
//protocol DisplayLinkDriver: AnyObject {
//    var onTick: ((CFTimeInterval) -> Void)? { get set }
//    var isRunning: Bool { get }
//    func setAnchorView(_ view: NSView?)
//    func start()
//    func stop()
//    func invalidate()
//}
//
//final class ViewDisplayLinkDriver: NSObject, DisplayLinkDriver {
//    var onTick: ((CFTimeInterval) -> Void)?
//    private weak var anchorView: NSView?
//    private var displayLink: CADisplayLink?
//
//    var isRunning: Bool {
//        displayLink != nil
//    }
//
//    func setAnchorView(_ view: NSView?) {
//        guard anchorView !== view else { return }
//        anchorView = view
//        guard isRunning else { return }
//        stop()
//        start()
//    }
//
//    func start() {
//        guard displayLink == nil, let anchorView else { return }
//        let link = anchorView.displayLink(target: self, selector: #selector(handleDisplayLinkTick(_:)))
//        link.add(to: .main, forMode: .common)
//        displayLink = link
//    }
//
//    func stop() {
//        displayLink?.invalidate()
//        displayLink = nil
//    }
//
//    func invalidate() {
//        stop()
//        anchorView = nil
//        onTick = nil
//    }
//    
//    @objc
//    private func handleDisplayLinkTick(_ displayLink: CADisplayLink) {
//        onTick?(displayLink.timestamp)
//    }
//}
//
//final class HeaderSnapshotStore {
//    struct Configuration: Equatable {
//        var targetSize: CGSize = .zero
//        var isLiveCaptureEnabled = false
//    }
//
//    weak var sourceView: NSView?
//    weak var captureView: NSView?
//    var onFrameRendered: ((NSImage) -> Void)?
//
//    private let driver: DisplayLinkDriver
//    private var configuration = Configuration()
//
//    private var lastCaptureTimestamp: CFTimeInterval = 0
//    private var isCaptureScheduled = false
//    private var hasPendingForcedCapture = false
//    private var lastCapturedSourceRect: CGRect = .null
//    private var applicationObservers: [NSObjectProtocol] = []
//
//    private let maxFPS: Double = 60
//    private var minimumCaptureInterval: CFTimeInterval {
//        1.0 / maxFPS
//    }
//
//    init(driver: DisplayLinkDriver = ViewDisplayLinkDriver()) {
//        self.driver = driver
//        self.driver.onTick = { [weak self] timestamp in
//            self?.handleDisplayLinkTick(timestamp: timestamp)
//        }
//        observeApplicationLifecycle()
//    }
//
//    deinit {
//        applicationObservers.forEach(NotificationCenter.default.removeObserver)
//        driver.invalidate()
//    }
//
//    func updateConfiguration(_ newConfiguration: Configuration) {
//        let oldConfiguration = configuration
//        configuration = newConfiguration
//
//        if oldConfiguration.targetSize != newConfiguration.targetSize {
//            requestCapture(force: true)
//        }
//
//        if oldConfiguration.isLiveCaptureEnabled != newConfiguration.isLiveCaptureEnabled {
//            updateLiveCaptureState()
//        }
//    }
//
//    func registerSourceView(_ view: NSView) {
//        guard sourceView !== view else {
//            requestCapture(force: true)
//            updateLiveCaptureState()
//            return
//        }
//
//        sourceView = view
//        driver.setAnchorView(view)
//        lastCapturedSourceRect = .null
//        requestCapture(force: true)
//        updateLiveCaptureState()
//    }
//
//    func unregisterSourceView() {
//        sourceView = nil
//        driver.setAnchorView(nil)
//        lastCapturedSourceRect = .null
//        updateLiveCaptureState()
//    }
//
//    func registerCaptureView(_ view: NSView) {
//        guard captureView !== view else { return }
//        captureView = view
//        requestCapture(force: true)
//        updateLiveCaptureState()
//    }
//
//    func unregisterCaptureView() {
//        captureView = nil
//        updateLiveCaptureState()
//    }
//
//    func captureViewVisibilityDidChange() {
//        updateLiveCaptureState()
//        requestCapture(force: true)
//    }
//
//    func requestCapture(force: Bool = false) {
//        hasPendingForcedCapture = hasPendingForcedCapture || force
//        guard !isCaptureScheduled else { return }
//
//        isCaptureScheduled = true
//        DispatchQueue.main.async { [weak self] in
//            guard let self else { return }
//            self.isCaptureScheduled = false
//            let pendingForce = self.hasPendingForcedCapture
//            self.hasPendingForcedCapture = false
//            self.captureIfNeeded(force: pendingForce, timestamp: CACurrentMediaTime())
//        }
//    }
//
//    func stopLiveCapture() {
//        driver.stop()
//    }
//
//    private func observeApplicationLifecycle() {
//        let center = NotificationCenter.default
//        applicationObservers.append(
//            center.addObserver(
//                forName: NSApplication.didBecomeActiveNotification,
//                object: nil,
//                queue: .main
//            ) { [weak self] _ in
//                DispatchQueue.main.async {
//                    self?.captureViewVisibilityDidChange()
//                }
//            }
//        )
//        applicationObservers.append(
//            center.addObserver(
//                forName: NSApplication.didResignActiveNotification,
//                object: nil,
//                queue: .main
//            ) { [weak self] _ in
//                DispatchQueue.main.async {
//                    self?.captureViewVisibilityDidChange()
//                }
//            }
//        )
//    }
//
//    private func handleDisplayLinkTick(timestamp: CFTimeInterval) {
//        guard configuration.isLiveCaptureEnabled else {
//            driver.stop()
//            return
//        }
//
//        guard shouldCaptureNow else {
//            driver.stop()
//            return
//        }
//
//        captureIfNeeded(force: false, timestamp: timestamp)
//    }
//
//    private var shouldCaptureNow: Bool {
//        guard let sourceView, let captureView else { return false }
//        guard captureView.window != nil, sourceView.window != nil else { return false }
//        guard captureView.window === sourceView.window else { return false }
//        guard configuration.targetSize.width > 1, configuration.targetSize.height > 1 else { return false }
//        guard !captureView.isHiddenOrHasHiddenAncestor, !sourceView.isHiddenOrHasHiddenAncestor else { return false }
//        guard sourceView.alphaValue > 0.01, captureView.alphaValue > 0.01 else { return false }
//
//        if let window = captureView.window {
//            guard window.isVisible else { return false }
//        }
//
//        return true
//    }
//
//    private func updateLiveCaptureState() {
//        if configuration.isLiveCaptureEnabled, shouldCaptureNow {
//            driver.start()
//            requestCapture(force: true)
//        } else {
//            driver.stop()
//        }
//    }
//
//    private func captureIfNeeded(force: Bool, timestamp: CFTimeInterval) {
//        guard shouldCaptureNow else { return }
//
//        if !force, timestamp - lastCaptureTimestamp < minimumCaptureInterval {
//            return
//        }
//
//        guard let sourceView, let captureView else { return }
//
//        let captureRectInWindow = captureView.convert(captureView.bounds, to: nil)
//        let sourceRect = sourceView.convert(captureRectInWindow, from: nil).intersection(sourceView.bounds)
//        
//        guard sourceRect.width > 1, sourceRect.height > 1 else { return }
//
//        if !force, sourceRect.equalTo(lastCapturedSourceRect), configuration.isLiveCaptureEnabled == false {
//            return
//        }
//
//        guard let image = renderedImage(
//            from: sourceView,
//            sourceRect: sourceRect,
//            targetSize: configuration.targetSize
//        ) else {
//            return
//        }
//    
//        lastCaptureTimestamp = timestamp
//        lastCapturedSourceRect = sourceRect
//        onFrameRendered?(image)
//    }
//
//    private func renderedImage(
//        from sourceView: NSView,
//        sourceRect: CGRect,
//        targetSize: CGSize
//    ) -> NSImage? {
//        guard let sourceBitmap = sourceView.bitmapImageRepForCachingDisplay(in: sourceRect) else {
//            return nil
//        }
//
//        sourceBitmap.size = sourceRect.size
//        sourceView.cacheDisplay(in: sourceRect, to: sourceBitmap)
//
//        guard let destinationBitmap = makeDestinationBitmap(targetSize: targetSize) else {
//            return nil
//        }
//
//        NSGraphicsContext.saveGraphicsState()
//        guard let context = NSGraphicsContext(bitmapImageRep: destinationBitmap) else {
//            NSGraphicsContext.restoreGraphicsState()
//            return nil
//        }
//
//        NSGraphicsContext.current = context
//        context.imageInterpolation = .high
//
//        let destinationRect = CGRect(origin: .zero, size: targetSize)
//        NSColor.clear.setFill()
//        destinationRect.fill()
//
//        sourceBitmap.draw(
//            in: destinationRect,
//            from: CGRect(origin: .zero, size: sourceRect.size),
//            operation: .sourceOver,
//            fraction: 1.0,
//            respectFlipped: true,
//            hints: [.interpolation: NSImageInterpolation.high]
//        )
//
//        context.flushGraphics()
//        NSGraphicsContext.restoreGraphicsState()
//
//        let image = NSImage(size: targetSize)
//        image.addRepresentation(destinationBitmap)
//        return image
//    }
//
//    private func makeDestinationBitmap(targetSize: CGSize) -> NSBitmapImageRep? {
//        let pixelWidth = max(Int(targetSize.width.rounded(.up)), 1)
//        let pixelHeight = max(Int(targetSize.height.rounded(.up)), 1)
//
//        let bitmap = NSBitmapImageRep(
//            bitmapDataPlanes: nil,
//            pixelsWide: pixelWidth,
//            pixelsHigh: pixelHeight,
//            bitsPerSample: 8,
//            samplesPerPixel: 4,
//            hasAlpha: true,
//            isPlanar: false,
//            colorSpaceName: .deviceRGB,
//            bytesPerRow: 0,
//            bitsPerPixel: 0
//        )
//
//        bitmap?.size = CGSize(width: pixelWidth, height: pixelHeight)
//        return bitmap
//    }
//}
//
