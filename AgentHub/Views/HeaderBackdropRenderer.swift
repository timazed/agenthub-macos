//
//  HeaderBackdropRenderer.swift
//  AgentHub
//
//  Created by Timothy Zelinsky on 13/3/2026.
//
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

final class HeaderBackdropRenderer {
    struct Configuration: Equatable {
        var outputSize: CGSize = .zero
        var blurRadius: CGFloat = 20
        var blurStartPoint: CGFloat = 0
        var blurEndPoint: CGFloat = 1
        var scaleFactor: CGFloat = 1
    }

    var onFrameReady: ((CGImage) -> Void)?

    private let renderQueue = DispatchQueue(label: "HeaderBackdropRenderer.render", qos: .userInteractive)
    private let ciContext = CIContext(options: [
        .cacheIntermediates: true
    ])

    private var configuration = Configuration()
    private var isRendering = false
    private var pendingRequest: RenderRequest?

    private var cachedMaskImage: CIImage?
    private var cachedMaskKey: MaskKey?

    private struct RenderRequest {
        let sourceImage: CGImage
        let sourceRect: CGRect
        let requestID: UInt64
    }

    private struct MaskKey: Equatable {
        let width: Int
        let height: Int
        let startPoint: CGFloat
        let endPoint: CGFloat
    }

    func updateConfiguration(_ newConfiguration: Configuration) {
        configuration = newConfiguration
    }

    func enqueueRender(sourceImage: CGImage, sourceRect: CGRect, requestID: UInt64) {
//        let request = RenderRequest(
//            sourceImage: sourceImage,
//            sourceRect: sourceRect,
//            requestID: requestID
//        )
//
//        renderQueue.async { [weak self] in
//            guard let self else { return }
//            self.pendingRequest = request
//            self.kickRenderLoopIfNeeded()
//        }
        
        self.onFrameReady?(sourceImage)

    }

    private func kickRenderLoopIfNeeded() {
        guard !isRendering else { return }
        isRendering = true

        renderQueue.async { [weak self] in
            self?.renderLoop()
        }
    }

    private func renderLoop() {
        while let request = pendingRequest {
            pendingRequest = nil

            guard let output = render(request: request) else { continue }

            DispatchQueue.main.async { [weak self] in
                self?.onFrameReady?(output)
            }
        }

        isRendering = false

        if pendingRequest != nil {
            kickRenderLoopIfNeeded()
        }
    }

    private func render(request: RenderRequest) -> CGImage? {
        let outputSize = configuration.outputSize.integralCeil
        guard outputSize.width > 0, outputSize.height > 0 else { return nil }

        let sourceCI = CIImage(cgImage: request.sourceImage)

        let cropped = sourceCI.cropped(to: request.sourceRect)
        let scaled = cropped.transformed(
            by: CGAffineTransform(
                scaleX: outputSize.width / request.sourceRect.width,
                y: outputSize.height / request.sourceRect.height
            )
        )

        let outputRect = CGRect(origin: .zero, size: outputSize)

        let mask = variableBlurMask(for: outputSize)
        let variableBlur = CIFilter.maskedVariableBlur()
        variableBlur.inputImage = scaled
        variableBlur.mask = mask
        variableBlur.radius = Float(configuration.blurRadius)

        let blurred = (variableBlur.outputImage ?? scaled).cropped(to: outputRect)

        return ciContext.createCGImage(blurred, from: outputRect)
    }

    private func variableBlurMask(for size: CGSize) -> CIImage {
        let key = MaskKey(
            width: max(Int(size.width.rounded(.up)), 1),
            height: max(Int(size.height.rounded(.up)), 1),
            startPoint: configuration.blurStartPoint,
            endPoint: configuration.blurEndPoint
        )

        if let cachedMaskImage, let cachedMaskKey, cachedMaskKey == key {
            return cachedMaskImage
        }

        let startY = size.height * configuration.blurStartPoint
        let endY = size.height * configuration.blurEndPoint

        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: 0, y: startY)
        gradient.point1 = CGPoint(x: 0, y: endY)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)

        let image = (gradient.outputImage ?? CIImage.empty())
            .cropped(to: CGRect(origin: .zero, size: size))

        cachedMaskKey = key
        cachedMaskImage = image
        return image
    }
}

private extension CGSize {
    var integralCeil: CGSize {
        CGSize(width: ceil(width), height: ceil(height))
    }
}
