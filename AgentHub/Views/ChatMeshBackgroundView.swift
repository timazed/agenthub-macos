import MeshingKit
import SwiftUI
import simd

struct ChatMeshBackgroundView: View {
    var isAnimated = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isAnimated)) { timeline in
            ChatMeshGradientLayer(date: timeline.date)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

struct ChatMeshGradientLayer: View {
    let date: Date
    var blurRadius: CGFloat = 4
    var saturation: CGFloat = 1.18
    var contrast: CGFloat = 1.08
    var scale: CGFloat = 1.03

    var body: some View {
        MeshGradient(
            width: Self.template.size,
            height: Self.template.size,
            locations: .points(Self.animatedPoints(for: date)),
            colors: .colors(Self.template.colors),
            background: Self.template.background,
            smoothsColors: true
        )
        .blur(radius: blurRadius)
        .saturation(saturation)
        .contrast(contrast)
        .scaleEffect(scale)
    }
}

private extension ChatMeshGradientLayer {
    static let animationSpeed: Double = 1.75

    static let template = CustomGradientTemplate(
        name: "Chat Mesh Background",
        size: 4,
        points: [
            SIMD2<Float>(0.00, 0.00), SIMD2<Float>(0.12, 0.00), SIMD2<Float>(0.66, 0.00), SIMD2<Float>(1.00, 0.00),
            SIMD2<Float>(0.00, 0.24), SIMD2<Float>(0.24, 0.18), SIMD2<Float>(0.71, 0.24), SIMD2<Float>(1.00, 0.18),
            SIMD2<Float>(0.00, 0.74), SIMD2<Float>(0.18, 0.78), SIMD2<Float>(0.74, 0.72), SIMD2<Float>(1.00, 0.82),
            SIMD2<Float>(0.00, 1.00), SIMD2<Float>(0.24, 1.00), SIMD2<Float>(0.74, 1.00), SIMD2<Float>(1.00, 1.00)
        ],
        colors: [
            Color(hex: "#F66DDE"), Color(hex: "#51B4F8"), Color(hex: "#A5B1FA"), Color(hex: "#F070DA"),
            Color(hex: "#F167DA"), Color(hex: "#35AFF7"), Color(hex: "#93B0F8"), Color(hex: "#EE76DC"),
            Color(hex: "#EE69D7"), Color(hex: "#41B4F4"), Color(hex: "#9E9EF1"), Color(hex: "#EA6ED8"),
            Color(hex: "#E064D3"), Color(hex: "#7FAAF2"), Color(hex: "#B58FEC"), Color(hex: "#F16CDB")
        ],
        background: Color(hex: "#C9C7F6")
    )

    static let animationPattern = AnimationPattern(animations: [
        PointAnimation(pointIndex: 1, axis: .x, amplitude: 0.22, frequency: 0.74),
        PointAnimation(pointIndex: 5, axis: .both, amplitude: 0.18, frequency: 0.58),
        PointAnimation(pointIndex: 9, axis: .both, amplitude: -0.18, frequency: 0.64),
        PointAnimation(pointIndex: 13, axis: .x, amplitude: 0.16, frequency: 0.70),
        PointAnimation(pointIndex: 2, axis: .x, amplitude: -0.12, frequency: 0.48),
        PointAnimation(pointIndex: 6, axis: .both, amplitude: 0.14, frequency: 0.54),
        PointAnimation(pointIndex: 10, axis: .both, amplitude: -0.12, frequency: 0.60)
    ])

    static func animatedPoints(for date: Date) -> [SIMD2<Float>] {
        let phase = date.timeIntervalSinceReferenceDate * animationSpeed
        var animated = template.points

        for animation in animationPattern.animations where animation.pointIndex < animated.count {
            let value = Float(cos(phase * Double(animation.frequency)))
            let amplitude = Float(animation.amplitude)

            switch animation.axis {
            case .x:
                animated[animation.pointIndex].x += amplitude * value
            case .y:
                animated[animation.pointIndex].y += amplitude * value
            case .both:
                animated[animation.pointIndex].x += amplitude * value
                animated[animation.pointIndex].y += amplitude * Float(sin(phase * Double(animation.frequency)))
            }
        }

        return animated.map { point in
            SIMD2<Float>(
                min(max(point.x, 0), 1),
                min(max(point.y, 0), 1)
            )
        }
    }
}
