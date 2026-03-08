import SwiftUI

struct OnboardingPalette {
    let canvas: [Color]
    let glowA: Color
    let glowB: Color
    let panelFill: Color
    let panelStroke: Color
    let secondaryPanelFill: Color
    let secondaryPanelStroke: Color
    let title: Color
    let body: Color
    let subdued: Color
    let fieldFill: Color
    let fieldStroke: Color
    let accent: Color
    let accentSoft: Color
    let error: Color
    let shadow: Color

    static func resolve(for colorScheme: ColorScheme) -> OnboardingPalette {
        if colorScheme == .dark {
            return OnboardingPalette(
                canvas: [
                    Color(red: 0.03, green: 0.05, blue: 0.08),
                    Color(red: 0.06, green: 0.08, blue: 0.13),
                    Color(red: 0.02, green: 0.03, blue: 0.05)
                ],
                glowA: Color(red: 0.22, green: 0.54, blue: 0.70).opacity(0.34),
                glowB: Color(red: 0.96, green: 0.71, blue: 0.42).opacity(0.18),
                panelFill: Color.white.opacity(0.07),
                panelStroke: Color.white.opacity(0.12),
                secondaryPanelFill: Color.black.opacity(0.20),
                secondaryPanelStroke: Color.white.opacity(0.08),
                title: Color.white.opacity(0.98),
                body: Color.white.opacity(0.76),
                subdued: Color.white.opacity(0.56),
                fieldFill: Color.black.opacity(0.24),
                fieldStroke: Color.white.opacity(0.10),
                accent: Color(red: 0.53, green: 0.79, blue: 0.95),
                accentSoft: Color(red: 0.53, green: 0.79, blue: 0.95).opacity(0.18),
                error: Color(red: 1.0, green: 0.74, blue: 0.74),
                shadow: Color.black.opacity(0.28)
            )
        }

        return OnboardingPalette(
            canvas: [
                Color(red: 0.97, green: 0.98, blue: 1.0),
                Color(red: 0.93, green: 0.96, blue: 0.99),
                Color(red: 0.98, green: 0.97, blue: 0.95)
            ],
            glowA: Color(red: 0.28, green: 0.60, blue: 0.76).opacity(0.18),
            glowB: Color(red: 0.93, green: 0.65, blue: 0.34).opacity(0.14),
            panelFill: Color.white.opacity(0.72),
            panelStroke: Color.black.opacity(0.08),
            secondaryPanelFill: Color.white.opacity(0.52),
            secondaryPanelStroke: Color.black.opacity(0.06),
            title: Color.black.opacity(0.88),
            body: Color.black.opacity(0.66),
            subdued: Color.black.opacity(0.48),
            fieldFill: Color.white.opacity(0.74),
            fieldStroke: Color.black.opacity(0.08),
            accent: Color(red: 0.10, green: 0.42, blue: 0.66),
            accentSoft: Color(red: 0.10, green: 0.42, blue: 0.66).opacity(0.10),
            error: Color(red: 0.67, green: 0.16, blue: 0.17),
            shadow: Color(red: 0.25, green: 0.29, blue: 0.35).opacity(0.10)
        )
    }
}

struct OnboardingExperienceBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = OnboardingPalette.resolve(for: colorScheme)

        ZStack {
            LinearGradient(
                colors: palette.canvas,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(palette.glowA)
                .frame(width: 420, height: 420)
                .blur(radius: 30)
                .offset(x: -220, y: -230)

            Circle()
                .fill(palette.glowB)
                .frame(width: 360, height: 360)
                .blur(radius: 45)
                .offset(x: 250, y: 210)
        }
        .ignoresSafeArea()
    }
}

struct OnboardingShell<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let maxWidth: CGFloat
    @ViewBuilder let content: Content

    init(maxWidth: CGFloat = 1180, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        let palette = OnboardingPalette.resolve(for: colorScheme)

        ZStack {
            OnboardingExperienceBackground()

            content
                .padding(24)
                .frame(maxWidth: maxWidth, maxHeight: .infinity)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(palette.panelStroke.opacity(colorScheme == .dark ? 0.65 : 0.8), lineWidth: 1)
                .padding(18)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }
}

struct OnboardingPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let padding: CGFloat
    @ViewBuilder let content: Content

    init(padding: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        let palette = OnboardingPalette.resolve(for: colorScheme)

        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(palette.panelFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(palette.panelStroke, lineWidth: 1)
                    )
                    .shadow(color: palette.shadow, radius: 24, x: 0, y: 12)
                    .background(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
    }
}

struct OnboardingSecondaryPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let palette = OnboardingPalette.resolve(for: colorScheme)

        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(palette.secondaryPanelFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(palette.secondaryPanelStroke, lineWidth: 1)
                    )
            )
    }
}
