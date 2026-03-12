import SwiftUI
import AppKit
import Combine
import QuartzCore
import VariableBlurImageView

@MainActor
final class HeaderSnapshotStore: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    weak var scrollView: NSScrollView? {
        didSet {
            guard oldValue !== scrollView else { return }
            objectWillChange.send()
        }
    }

    weak var snapshotSourceView: NSView? {
        didSet {
            guard oldValue !== snapshotSourceView else { return }
            sourceGeneration &+= 1
            objectWillChange.send()
        }
    }

    private(set) var sourceGeneration = 0
}

struct ScrollActivityObserver: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    let onScrollEnded: () -> Void
    let onScrollViewResolved: (NSScrollView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll, onScrollEnded: onScrollEnded, onScrollViewResolved: onScrollViewResolved)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.onScrollEnded = onScrollEnded
        context.coordinator.onScrollViewResolved = onScrollViewResolved
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView)
        }
    }

    final class Coordinator {
        var onScroll: (CGFloat) -> Void
        var onScrollEnded: () -> Void
        var onScrollViewResolved: (NSScrollView) -> Void
        private weak var observedClipView: NSClipView?
        private weak var observedScrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var liveScrollObserver: NSObjectProtocol?
        private var liveScrollEndObserver: NSObjectProtocol?
        private var lastScrollSample: (time: CFTimeInterval, y: CGFloat)?

        init(
            onScroll: @escaping (CGFloat) -> Void,
            onScrollEnded: @escaping () -> Void,
            onScrollViewResolved: @escaping (NSScrollView) -> Void
        ) {
            self.onScroll = onScroll
            self.onScrollEnded = onScrollEnded
            self.onScrollViewResolved = onScrollViewResolved
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let liveScrollObserver {
                NotificationCenter.default.removeObserver(liveScrollObserver)
            }
            if let liveScrollEndObserver {
                NotificationCenter.default.removeObserver(liveScrollEndObserver)
            }
        }

        func attach(to view: NSView) {
            guard let scrollView = resolveScrollView(from: view) else { return }
            let clipView = scrollView.contentView
            onScrollViewResolved(scrollView)
            let clipViewChanged = clipView !== observedClipView
            let scrollViewChanged = scrollView !== observedScrollView
            guard clipViewChanged || scrollViewChanged else { return }

            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let liveScrollObserver {
                NotificationCenter.default.removeObserver(liveScrollObserver)
            }
            if let liveScrollEndObserver {
                NotificationCenter.default.removeObserver(liveScrollEndObserver)
            }

            observedClipView = clipView
            observedScrollView = scrollView
            clipView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.recordScrollSample(from: clipView)
            }
            liveScrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                self?.lastScrollSample = (CACurrentMediaTime(), clipView.bounds.origin.y)
                self?.onScroll(0)
            }
            liveScrollEndObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                self?.lastScrollSample = nil
                self?.onScrollEnded()
            }
        }

        private func recordScrollSample(from clipView: NSClipView) {
            let now = CACurrentMediaTime()
            let y = clipView.bounds.origin.y
            let velocity: CGFloat
            if let lastScrollSample {
                let deltaTime = max(now - lastScrollSample.time, 0.001)
                velocity = abs((y - lastScrollSample.y) / CGFloat(deltaTime))
            } else {
                velocity = 0
            }
            lastScrollSample = (now, y)
            onScroll(velocity)
        }

        private func resolveScrollView(from view: NSView) -> NSScrollView? {
            if let scrollView = view.enclosingScrollView {
                return scrollView
            }

            var candidate = view.superview
            while let current = candidate {
                if let scrollView = current as? NSScrollView {
                    return scrollView
                }
                if let scrollView = current.enclosingScrollView {
                    return scrollView
                }
                candidate = current.superview
            }

            var responder: NSResponder? = view.nextResponder
            while let current = responder {
                if let scrollView = current as? NSScrollView {
                    return scrollView
                }
                responder = current.nextResponder
            }

            guard let rootView = view.window?.contentView else { return nil }
            let targetFrameInWindow = view.convert(view.bounds, to: nil)
            return nearestScrollView(to: targetFrameInWindow, in: rootView)
        }

        private func nearestScrollView(to targetFrameInWindow: CGRect, in rootView: NSView) -> NSScrollView? {
            var queue: [NSView] = [rootView]
            var bestMatch: (scrollView: NSScrollView, area: CGFloat)?

            while !queue.isEmpty {
                let current = queue.removeFirst()
                if let scrollView = current as? NSScrollView {
                    let frameInWindow = scrollView.convert(scrollView.bounds, to: nil)
                    let intersection = frameInWindow.intersection(targetFrameInWindow)
                    let area = intersection.width * intersection.height
                    if area > 0, area > (bestMatch?.area ?? 0) {
                        bestMatch = (scrollView, area)
                    }
                }
                queue.append(contentsOf: current.subviews)
            }

            if let bestMatch {
                return bestMatch.scrollView
            }
            return nil
        }
    }
}

struct ChatSceneSnapshotSourceObserver: NSViewRepresentable {
    @ObservedObject var store: HeaderSnapshotStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughSurfaceView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.store = store
        context.coordinator.attach(to: nsView)
    }

    final class Coordinator {
        weak var store: HeaderSnapshotStore?

        init(store: HeaderSnapshotStore) {
            self.store = store
        }

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.resolveSourceView(from: view)
            }
        }

        private func resolveSourceView(from view: NSView) {
            guard let store else { return }
            guard
                let scrollView = store.scrollView,
                let sourceView = lowestCommonAncestor(between: view, and: scrollView)
            else {
                store.snapshotSourceView = nil
                return
            }

            store.snapshotSourceView = sourceView
        }

        private func lowestCommonAncestor(between first: NSView, and second: NSView) -> NSView? {
            var ancestors: Set<ObjectIdentifier> = []
            var current: NSView? = first
            while let node = current {
                ancestors.insert(ObjectIdentifier(node))
                current = node.superview
            }

            current = second
            while let node = current {
                if ancestors.contains(ObjectIdentifier(node)) {
                    return node
                }
                current = node.superview
            }

            return nil
        }
    }

    final class PassthroughSurfaceView: NSView {
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

struct HeaderSnapshotSurfaceView: NSViewRepresentable {
    @ObservedObject var store: HeaderSnapshotStore
    let width: CGFloat
    let headerHeight: CGFloat
    let refreshID: Int
    let isLiveCaptureEnabled: Bool

    private var configuration: SnapshotSurfaceView.Configuration {
        .init(
            targetSize: CGSize(width: width, height: headerHeight),
            refreshID: refreshID,
            sourceGeneration: store.sourceGeneration,
            isLiveCaptureEnabled: isLiveCaptureEnabled
        )
    }

    func makeNSView(context: Context) -> SnapshotSurfaceView {
        let view = SnapshotSurfaceView()
        view.update(store: store, configuration: configuration)
        view.captureIfNeeded(force: true)
        return view
    }

    func updateNSView(_ nsView: SnapshotSurfaceView, context: Context) {
        nsView.update(store: store, configuration: configuration)
        nsView.captureIfNeeded()
    }

    final class SnapshotSurfaceView: NSView {
        struct Configuration: Equatable {
            let targetSize: CGSize
            let refreshID: Int
            let sourceGeneration: Int
            let isLiveCaptureEnabled: Bool
        }

        private let imageView = VariableBlurImageView()

        weak var store: HeaderSnapshotStore?
        private var configuration = Configuration(
            targetSize: .zero,
            refreshID: 0,
            sourceGeneration: 0,
            isLiveCaptureEnabled: false
        )
        private var lastRenderedConfiguration: Configuration?
        private var isCaptureScheduled = false
        private var hasPendingForcedCapture = false
        private var liveCaptureDisplayLink: CADisplayLink?
        private var lastLiveCaptureTimestamp: CFTimeInterval = 0

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = true
            imageView.frame = bounds
            imageView.autoresizingMask = [.width, .height]
            imageView.imageScaling = .scaleProportionallyUpOrDown
            addSubview(imageView)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            stopLiveCapture()
        }

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateLiveCaptureIfNeeded()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        func update(store: HeaderSnapshotStore, configuration: Configuration) {
            self.store = store
            self.configuration = configuration
            updateLiveCaptureIfNeeded()
        }

        func captureIfNeeded(force: Bool = false) {
            hasPendingForcedCapture = hasPendingForcedCapture || force
            guard !isCaptureScheduled else { return }

            isCaptureScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isCaptureScheduled = false
                let pendingForce = self.hasPendingForcedCapture
                self.hasPendingForcedCapture = false
                self.performCaptureIfNeeded(force: pendingForce)
            }
        }

        private func performCaptureIfNeeded(force: Bool) {
            let currentConfiguration = configuration
            guard currentConfiguration.targetSize.width > 0, currentConfiguration.targetSize.height > 0 else {
                return
            }
            if !force, lastRenderedConfiguration == currentConfiguration {
                return
            }
            guard let image = captureSlice(targetSize: currentConfiguration.targetSize) else {
                return
            }

            imageView.verticalVariableBlur(
                image: image,
                startPoint: 0,
                endPoint: image.size.height * 0.9,
                startRadius: 7,
                endRadius: 1.5
            )
            lastRenderedConfiguration = currentConfiguration
        }

        private func updateLiveCaptureIfNeeded() {
            guard configuration.isLiveCaptureEnabled, window != nil else {
                stopLiveCapture()
                return
            }

            guard liveCaptureDisplayLink == nil else { return }

            let displayLink = self.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
            displayLink.add(to: .main, forMode: .common)
            liveCaptureDisplayLink = displayLink
            lastLiveCaptureTimestamp = 0
        }

        private func stopLiveCapture() {
            liveCaptureDisplayLink?.invalidate()
            liveCaptureDisplayLink = nil
            lastLiveCaptureTimestamp = 0
        }

        @objc
        private func displayLinkDidFire(_ displayLink: CADisplayLink) {
            guard configuration.isLiveCaptureEnabled else { return }
            guard displayLink.timestamp - lastLiveCaptureTimestamp >= (1.0 / 30.0) else { return }

            lastLiveCaptureTimestamp = displayLink.timestamp
            captureIfNeeded(force: true)
        }

        private func captureSlice(targetSize: CGSize) -> NSImage? {
            if let sourceView = store?.snapshotSourceView {
                let rectInWindow = convert(bounds, to: nil)
                let sourceRect = sourceView.convert(rectInWindow, from: nil).integral.intersection(sourceView.bounds)
                guard sourceRect.width > 1, sourceRect.height > 1 else { return nil }
                return renderedImage(from: sourceView, sourceRect: sourceRect, targetSize: targetSize)
            }

            guard
                let scrollView = store?.scrollView,
                let documentView = scrollView.documentView
            else {
                return nil
            }

            let rectInWindow = convert(bounds, to: nil)
            let rectInDocument = documentView.convert(rectInWindow, from: nil)
            let sourceRect = rectInDocument.integral.intersection(documentView.bounds)
            guard sourceRect.width > 1, sourceRect.height > 1 else { return nil }

            return renderedImage(from: documentView, sourceRect: sourceRect, targetSize: targetSize)
        }

        private func renderedImage(
            from sourceView: NSView,
            sourceRect: CGRect,
            targetSize: CGSize
        ) -> NSImage? {
            guard let sourceBitmap = sourceView.bitmapImageRepForCachingDisplay(in: sourceRect) else {
                return nil
            }

            sourceBitmap.size = sourceRect.size
            sourceView.cacheDisplay(in: sourceRect, to: sourceBitmap)

            guard let destinationBitmap = makeDestinationBitmap(targetSize: targetSize) else {
                return nil
            }

            NSGraphicsContext.saveGraphicsState()
            guard let context = NSGraphicsContext(bitmapImageRep: destinationBitmap) else {
                NSGraphicsContext.restoreGraphicsState()
                return nil
            }
            
            NSGraphicsContext.current = context
            context.imageInterpolation = .high

            let destinationRect = CGRect(origin: .zero, size: targetSize)
            NSColor.clear.setFill()
            destinationRect.fill()

            sourceBitmap.draw(
                in: destinationRect,
                from: CGRect(origin: .zero, size: sourceRect.size),
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()

            let image = NSImage(size: targetSize)
            image.addRepresentation(destinationBitmap)
            return image
        }

        private func makeDestinationBitmap(targetSize: CGSize) -> NSBitmapImageRep? {
            let pixelWidth = max(Int(targetSize.width.rounded(.up)), 1)
            let pixelHeight = max(Int(targetSize.height.rounded(.up)), 1)

            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
            bitmap?.size = targetSize
            return bitmap
        }
    }
}
