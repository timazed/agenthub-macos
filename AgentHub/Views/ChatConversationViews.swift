import SwiftUI

enum ConversationScrollTarget: Hashable {
    case message(UUID)
    case thinking
}

enum ConversationViewportCoordinateSpace {
    static let name = "conversation-viewport"
}

enum ConversationBackdropDisplayMode {
    case live
    case backdrop
}

struct ConversationContentMinYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ConversationEntry: Identifiable {
    enum Kind {
        case separator(String)
        case message(Message)
        case thinking
    }

    let id: String
    let kind: Kind

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case let .separator(label):
            id = "separator-\(label)"
        case let .message(message):
            id = "message-\(message.id.uuidString)"
        case .thinking:
            id = "thinking"
        }
    }
}

struct DateSeparator: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    var displayMode: ConversationBackdropDisplayMode = .live

    var body: some View {
        Group {
            if displayMode == .live {
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.secondary.opacity(colorScheme == .dark ? 0.8 : 0.9))
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
            } else {
                Color.clear
                    .frame(height: 24)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct ConversationBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: Message
    let theme: AppTheme
    var displayMode: ConversationBackdropDisplayMode = .live

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isIncoming {
                bubble
                Spacer(minLength: 120)
            } else {
                Spacer(minLength: 120)
                bubble
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bubble: some View {
        bubbleContent
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                bubbleShape
                    .fill(bubbleFill)
                    .overlay(
                        bubbleShape
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
            .shadow(color: bubbleShadowColor, radius: isIncoming ? 0 : 10, x: 0, y: isIncoming ? 0 : 6)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if displayMode == .live {
            Text(message.text)
                .textSelection(.enabled)
                .font(.body)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.leading)
        } else {
            Text(message.text)
                .font(.body)
                .foregroundStyle(.clear)
                .multilineTextAlignment(.leading)
        }
    }

    private var isIncoming: Bool {
        message.role != .user
    }

    private var textColor: Color {
        if displayMode == .backdrop {
            return .clear
        }
        if theme == .bubbleGum {
            return .white.opacity(0.96)
        }
        return isIncoming ? Color.primary.opacity(0.92) : .white
    }

    private var bubbleFill: some ShapeStyle {
        if theme == .default {
            if isIncoming {
                return AnyShapeStyle(Color.primary.opacity(backdropAdjustedOpacity(colorScheme == .dark ? 0.14 : 0.08)))
            }
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.blue.opacity(backdropAdjustedOpacity(0.92)), Color.cyan.opacity(backdropAdjustedOpacity(0.72))],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        if isIncoming {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.28, green: 0.45, blue: 0.63).opacity(backdropAdjustedOpacity(colorScheme == .dark ? 0.62 : 0.54)),
                        Color(red: 0.34, green: 0.49, blue: 0.69).opacity(backdropAdjustedOpacity(colorScheme == .dark ? 0.56 : 0.48))
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [Color.blue.opacity(backdropAdjustedOpacity(0.94)), Color.cyan.opacity(backdropAdjustedOpacity(0.76))],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var borderColor: Color {
        if displayMode == .backdrop {
            return .clear
        }
        if theme == .default {
            return Color.primary.opacity(isIncoming ? (colorScheme == .dark ? 0.06 : 0.08) : 0.0)
        }
        if isIncoming {
            return Color.white.opacity(colorScheme == .dark ? 0.12 : 0.16)
        }
        return .clear
    }

    private var bubbleShadowColor: Color {
        if displayMode == .backdrop {
            return .clear
        }
        if theme == .default {
            return .clear
        }
        if isIncoming {
            return .clear
        }
        return Color.cyan.opacity(colorScheme == .dark ? 0.18 : 0.12)
    }

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme == .bubbleGum ? 20 : 18, style: .continuous)
    }

    private func backdropAdjustedOpacity(_ value: Double) -> Double {
        displayMode == .backdrop ? value * 0.42 : value
    }
}

struct ConversationThinkingRow: View {
    var body: some View {
        HStack {
            ThinkingStatusText()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ThinkingStatusText: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmerOffset: CGFloat = -1.2

    var body: some View {
        let text = Text("Thinking...")
            .font(.caption)

        text
            .foregroundStyle(baseColor)
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [.clear, highlightColor, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.85)
                    .offset(x: shimmerOffset * geometry.size.width)
                    .mask(
                        text.foregroundStyle(.white)
                    )
                }
                .allowsHitTesting(false)
            }
            .onAppear {
                shimmerOffset = -1.2
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.2
                }
            }
    }

    private var baseColor: Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.86 : 0.82)
    }

    private var highlightColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.95 : 0.72)
    }
}
