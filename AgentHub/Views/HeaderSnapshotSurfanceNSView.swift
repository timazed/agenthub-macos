//
//  HeaderSnapshotSurfanceNSView.swift
//  AgentHub
//
//  Created by Timothy Zelinsky on 12/3/2026.
//

//import AppKit
//import QuartzCore
//import VariableBlurImageView
//
//final class HeaderSnapshotSurfaceNSView: NSView {
//    private let imageView = VariableBlurImageView()
//    private let store = HeaderSnapshotStore()
//    private weak var currentSourceView: NSView?
//    private var lastLayoutSize: CGSize = .zero
//    private var lastApplyTime: CFTimeInterval = 0
//
//    override var isFlipped: Bool { true }
//
//    override init(frame frameRect: NSRect) {
//        super.init(frame: frameRect)
//
//        wantsLayer = true
//        layer?.masksToBounds = false
//
//        imageView.frame = bounds
//        imageView.autoresizingMask = [.width, .height]
//        imageView.imageScaling = .scaleProportionallyUpOrDown
//        addSubview(imageView)
//
//        store.onFrameRendered = { [weak self] image in
//            self?.applyFrame(image)
//        }
//        store.registerCaptureView(self)
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//
//    deinit {
//        teardown()
//    }
//
//    override func layout() {
//        super.layout()
//        imageView.frame = bounds
//
//        guard bounds.size != lastLayoutSize else { return }
//        lastLayoutSize = bounds.size
//        store.requestCapture(force: true)
//    }
//
//    override func viewDidMoveToWindow() {
//        super.viewDidMoveToWindow()
//        store.captureViewVisibilityDidChange()
//    }
//
//    override func viewDidHide() {
//        super.viewDidHide()
//        store.captureViewVisibilityDidChange()
//    }
//
//    override func viewDidUnhide() {
//        super.viewDidUnhide()
//        store.captureViewVisibilityDidChange()
//    }
//
//    override func hitTest(_ point: NSPoint) -> NSView? {
//        nil
//    }
//
//    func update(sourceView: NSView?, configuration: HeaderSnapshotStore.Configuration) {
//        store.updateConfiguration(configuration)
//
//        if currentSourceView !== sourceView {
//            currentSourceView = sourceView
//            if let sourceView {
//                store.registerSourceView(sourceView)
//            } else {
//                store.unregisterSourceView()
//            }
//        }
//    }
//
//    func teardown() {
//        store.onFrameRendered = nil
//        store.unregisterSourceView()
//        store.unregisterCaptureView()
//        store.stopLiveCapture()
//    }
//
//    private func applyFrame(_ image: NSImage) {
//        let now = CACurrentMediaTime()
//        guard now - lastApplyTime > (1.0 / 60.0) else { return }
//        lastApplyTime = now
//        imageView.verticalVariableBlur(
//            image: image,
//            startPoint: 0,
//            endPoint: image.size.height,
//            startRadius: 20,
//            endRadius: 1.5
//        )
//    }
//}

//
//  HeaderSnapshotSurfaceNSView.swift
//  AgentHub
//
//  Created by Timothy Zelinsky on 12/3/2026.
//

//import AppKit
//import QuartzCore
//
//final class HeaderSnapshotSurfaceNSView: NSView {
//    private let imageView = NSImageView()
//    private let store = HeaderSnapshotStore()
//
//    private weak var currentSourceView: NSView?
//    private var lastLayoutSize: CGSize = .zero
//    private var lastPresentedImageIdentifier: ObjectIdentifier?
//    private var isTornDown = false
//
//    override var isFlipped: Bool { true }
//
//    override init(frame frameRect: NSRect) {
//        super.init(frame: frameRect)
//
//        wantsLayer = true
//        layer?.masksToBounds = false
//
//        imageView.translatesAutoresizingMaskIntoConstraints = true
//        imageView.frame = bounds
//        imageView.autoresizingMask = [.width, .height]
//        imageView.imageAlignment = .alignCenter
//        imageView.imageScaling = .scaleAxesIndependently
//        imageView.animates = false
//        addSubview(imageView)
//
//        store.onFrameRendered = { [weak self] image in
//            self?.presentFrame(image)
//        }
//
//        store.registerCaptureView(self)
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//
//    deinit {
//        teardown()
//    }
//
//    override func layout() {
//        super.layout()
//
//        imageView.frame = bounds
//
//        guard bounds.size != lastLayoutSize else { return }
//        lastLayoutSize = bounds.size
//
//        store.requestCapture(force: true)
//    }
//
//    override func viewDidMoveToWindow() {
//        super.viewDidMoveToWindow()
//        store.captureViewVisibilityDidChange()
//    }
//
//    override func viewDidHide() {
//        super.viewDidHide()
//        store.captureViewVisibilityDidChange()
//    }
//
//    override func viewDidUnhide() {
//        super.viewDidUnhide()
//        store.captureViewVisibilityDidChange()
//    }
//
//    override func hitTest(_ point: NSPoint) -> NSView? {
//        nil
//    }
//
//    func update(sourceView: NSView?, configuration: HeaderSnapshotStore.Configuration) {
//        guard !isTornDown else { return }
//
//        store.updateConfiguration(configuration)
//
//        if currentSourceView !== sourceView {
//            currentSourceView = sourceView
//
//            if let sourceView {
//                store.registerSourceView(sourceView)
//            } else {
//                store.unregisterSourceView()
//                imageView.image = nil
//                lastPresentedImageIdentifier = nil
//            }
//        }
//    }
//
//    func teardown() {
//        guard !isTornDown else { return }
//        isTornDown = true
//
//        store.onFrameRendered = nil
//        store.unregisterSourceView()
//        store.unregisterCaptureView()
//        store.stopLiveCapture()
//
//        currentSourceView = nil
//        imageView.image = nil
//        lastPresentedImageIdentifier = nil
//    }
//
//    private func presentFrame(_ image: NSImage) {
//        guard !isTornDown else { return }
//
//        let identifier = ObjectIdentifier(image)
//        guard identifier != lastPresentedImageIdentifier else { return }
//
//        lastPresentedImageIdentifier = identifier
//        imageView.image = image
//    }
//}

import AppKit

final class HeaderSnapshotSurfaceNSView: NSView {
    struct Configuration: Equatable {
        var targetSize: CGSize = .zero
        var isLiveCaptureEnabled = false
        var maxFPS: Double = 30
        var blurRadius: CGFloat = 20
        var blurStartPoint: CGFloat = 0
        var blurEndPoint: CGFloat = 1
    }

    private let imageView = NSImageView()
    private let coordinator = HeaderBackdropCoordinator()

    private weak var currentSourceView: NSView?
    private var lastLayoutSize: CGSize = .zero
    private var isTornDown = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.masksToBounds = false

        imageView.translatesAutoresizingMaskIntoConstraints = true
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = false
        addSubview(imageView)

        coordinator.onFrameReady = { [weak self] image in
            self?.present(image)
        }

        coordinator.registerCaptureView(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        teardown()
    }

    override func layout() {
        super.layout()

        imageView.frame = bounds

        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        coordinator.requestCapture(force: true)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator.captureViewVisibilityDidChange()
    }

    override func viewDidHide() {
        super.viewDidHide()
        coordinator.captureViewVisibilityDidChange()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        coordinator.captureViewVisibilityDidChange()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(sourceView: NSView?, configuration: Configuration) {
        guard !isTornDown else { return }

        coordinator.updateConfiguration(
            .init(
                targetSize: configuration.targetSize,
                isLiveCaptureEnabled: configuration.isLiveCaptureEnabled,
                maxFPS: configuration.maxFPS,
                blurRadius: configuration.blurRadius,
                blurStartPoint: configuration.blurStartPoint,
                blurEndPoint: configuration.blurEndPoint
            )
        )

        if currentSourceView !== sourceView {
            currentSourceView = sourceView

            if let sourceView {
                coordinator.registerSourceView(sourceView)
            } else {
                coordinator.unregisterSourceView()
                imageView.image = nil
            }
        }
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true

        coordinator.onFrameReady = nil
        coordinator.unregisterSourceView()
        coordinator.unregisterCaptureView()
        coordinator.stopLiveCapture()

        currentSourceView = nil
        imageView.image = nil
    }

    private func present(_ cgImage: CGImage) {
        guard !isTornDown else { return }

        let size = bounds.size == .zero
            ? CGSize(width: cgImage.width, height: cgImage.height)
            : bounds.size

        imageView.image = NSImage(cgImage: cgImage, size: size)
    }
}
