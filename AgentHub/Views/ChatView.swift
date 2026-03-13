import SwiftUI
import AppKit
import Inferno
import MeshingKit

struct X: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                content
                    .blur(radius: 20)
                    .frame(height: 80)
                    .clipped()
            }
    }
}
struct ChatView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var viewModel: ChatViewModel
    let isPanelPresented: Bool
    let onTogglePanel: () -> Void
    let isInputEnabled: Bool
    let blockedMessage: String?

    @State private var composerHeight: CGFloat = ComposerMetrics.minTextHeight
    @State private var isModelMenuPresented = false
    @State private var isReasoningMenuPresented = false
    @StateObject private var snapshotBridge = SnapshotSourceBridge()

    private let topOverlayHeight: CGFloat = 56
    private let bottomOverlayHeight: CGFloat = 120
    private let headerBackdropHeight: CGFloat = 50 // (plus safe area padding)
    
    private var gradientAppearanceColor: Color {
        if viewModel.appTheme == .default {
            return colorScheme == .dark ? .black : .white
        }
        if viewModel.appTheme == .bubbleGum {
            return Color(hex: "#35AFF7")
        }
        return .white
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 30,
                paused: viewModel.appTheme != .bubbleGum
            )
        ) { timeline in
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    chatScene(
                        size: CGSize(
                            width: proxy.size.width,
                            height: proxy.size.height
                        ),
                        timelineDate: timeline.date
                    )
                    gradientTintOverlay
                    headerOverlay
                    composerOverlay
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func chatScene(size: CGSize, timelineDate: Date) -> some View {
        ZStack {
            themeBackground(timelineDate: timelineDate)
            conversationSurface
        }
        .ignoresSafeArea()
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(.clear)
    }

    @ViewBuilder
    private var conversationSurface: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                ZStack {
                    conversationEntriesStack(
                        useLazyLayout: true,
                        includeScrollTargets: true,
                        displayMode: .live
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, topOverlayHeight)
                    .padding(.bottom, bottomOverlayHeight)
                }
            }
            .background(.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentMargins(.top, 0, for: .scrollContent)
            .contentMargins(.bottom, 0, for: .scrollContent)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isThinking) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    @ViewBuilder
    private var gradientTintOverlay: some View {
        VStack {
            LinearGradient(
                stops: [
                    .init(color: gradientAppearanceColor.opacity(0.5), location: 0.0),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
            .frame(height: 80, alignment: . top)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.72),
                        .init(color: .black.opacity(0.75), location: 0.86),
                        .init(color: .black.opacity(0.28), location: 0.95),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )
            .allowsHitTesting(false)
            Spacer()
            LinearGradient(
                stops: [
                    .init(color: gradientAppearanceColor.opacity(0.5), location: 0.0),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea(edges: .bottom)
            .frame(height: 80, alignment: . bottom)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.72),
                        .init(color: .black.opacity(0.75), location: 0.86),
                        .init(color: .black.opacity(0.28), location: 0.95),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea(edges: .bottom)
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()

    }
        
    @ViewBuilder
    private var headerOverlay: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var composerOverlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            composer
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
        }
        .background(.clear)
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 6) {
            Button(action: onTogglePanel) {
                VStack(spacing: 6) {
                    ZStack {
                        AgentAvatarView(
                            name: viewModel.agentName,
                            profilePictureURL: viewModel.agentProfilePictureURL,
                            size: 32
                        )
                        .shadow(
                            color: overlayShade.opacity(colorScheme == .dark ? 0.22 : 0.12),
                            radius: 10,
                            x: 0,
                            y: 5
                        )
                    }

                    HStack(spacing: 8) {
                        Text(viewModel.agentName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.primary.opacity(0.96))

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.secondary.opacity(0.85))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.clear, in: .capsule(style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var composer: some View {
        VStack(spacing: 8) {
            if let proposal = viewModel.pendingProposal {
                PendingTaskProposalCard(
                    proposal: proposal,
                    onConfirm: { viewModel.confirmPendingProposal($0) },
                    onCancel: { viewModel.dismissPendingProposal() }
                )
            }

            HStack(alignment: .center, spacing: 8) {
                Button {
                    isReasoningMenuPresented = false
                    isModelMenuPresented.toggle()
                } label: {
                    BrainMenuButton(diameter: ComposerMetrics.controlHeight)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isThinking)
                .popover(
                    isPresented: $isModelMenuPresented,
                    attachmentAnchor: .point(.trailing),
                    arrowEdge: .trailing
                ) {
                    ModelPickerPopover(
                        models: viewModel.supportedModels,
                        activeModel: viewModel.activeModel,
                        onSelect: { model in
                            viewModel.setActiveModel(model)
                            isModelMenuPresented = false
                        }
                    )
                }

                Button {
                    isModelMenuPresented = false
                    isReasoningMenuPresented.toggle()
                } label: {
                    ReasoningMenuButton(diameter: ComposerMetrics.controlHeight)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isThinking)
                .popover(
                    isPresented: $isReasoningMenuPresented,
                    attachmentAnchor: .point(.trailing),
                    arrowEdge: .trailing
                ) {
                    ReasoningPickerPopover(
                        activeReasoning: viewModel.activeReasoning,
                        onSelect: { reasoning in
                            viewModel.setActiveReasoning(reasoning)
                            isReasoningMenuPresented = false
                        }
                    )
                }

                HStack(alignment: .center, spacing: 8) {
                    ComposerTextView(
                        text: $viewModel.inputText,
                        calculatedHeight: $composerHeight,
                        placeholder: "Ask me to do anything (one off or repeatable)",
                        colorScheme: colorScheme,
                        isEnabled: !viewModel.isBusy && isInputEnabled,
                        onSubmit: { viewModel.sendCurrentInput() }
                    )
                    .frame(height: composerHeight)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, ComposerMetrics.verticalPadding)
                .frame(minHeight: ComposerMetrics.controlHeight)
                .glassEffect(.clear, in: .capsule(style: .continuous))
                HStack(spacing: 8) {
                    CircleIconButton(
                        systemName: viewModel.isThinking ? "stop.fill" : "arrow.up",
                        diameter: ComposerMetrics.controlHeight
                    ) {
                        if viewModel.isBusy {
                            viewModel.cancel()
                        } else if !viewModel.inputText
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty {
                            viewModel.sendCurrentInput()
                        }
                    }
                }
            }

            if let blockedMessage, !isInputEnabled {
                Text(blockedMessage)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.52))
            }
        }
    }

    private var groupedEntries: [ConversationEntry] {
        var entries: [ConversationEntry] = []
        var lastLabel: String?

        for message in viewModel.messages {
            let label = separatorLabel(for: message.createdAt)
            if label != lastLabel {
                entries.append(.init(kind: .separator(label)))
                lastLabel = label
            }
            entries.append(.init(kind: .message(message)))
        }

        if viewModel.isThinking {
            entries.append(.init(kind: .thinking))
        }

        return entries
    }

    @ViewBuilder
    private func themeBackground(timelineDate: Date) -> some View {
        if viewModel.appTheme == .bubbleGum {
            ChatMeshGradientLayer(date: timelineDate)
                .ignoresSafeArea()
        } else {
            AdaptiveWindowBackground()
        }
    }

    @ViewBuilder
    private func conversationEntriesStack(
        useLazyLayout: Bool,
        includeScrollTargets: Bool,
        displayMode: ConversationBackdropDisplayMode
    ) -> some View {
        if useLazyLayout {
            LazyVStack(spacing: 18) {
                ForEach(groupedEntries) { entry in
                    conversationEntry(
                        entry,
                        includeScrollTargets: includeScrollTargets,
                        displayMode: displayMode
                    )
                }
            }
        } else {
            VStack(spacing: 18) {
                ForEach(groupedEntries) { entry in
                    conversationEntry(
                        entry,
                        includeScrollTargets: includeScrollTargets,
                        displayMode: displayMode
                    )
                }
            }
            .background(.clear)
        }
    }

    @ViewBuilder
    private func conversationEntry(
        _ entry: ConversationEntry,
        includeScrollTargets: Bool,
        displayMode: ConversationBackdropDisplayMode
    ) -> some View {
        switch entry.kind {
        case let .separator(label):
            DateSeparator(label: label, displayMode: displayMode)
        case let .message(message):
            if includeScrollTargets {
                ConversationBubble(
                    message: message,
                    theme: viewModel.appTheme,
                    displayMode: displayMode
                )
                .id(ConversationScrollTarget.message(message.id))
            } else {
                ConversationBubble(
                    message: message,
                    theme: viewModel.appTheme,
                    displayMode: displayMode
                )
            }
        case .thinking:
            if displayMode == .live, includeScrollTargets {
                ConversationThinkingRow()
                    .id(ConversationScrollTarget.thinking)
            } else if displayMode == .live {
                ConversationThinkingRow()
            } else {
                Color.clear
                    .frame(height: 18)
            }
        }
    }

    private func separatorLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today \(date.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date
            .formatted(
                .dateTime
                    .weekday(.wide)
                    .month(.abbreviated)
                    .day()
                    .hour()
                    .minute()
            )
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let target: ConversationScrollTarget?
        if viewModel.isThinking {
            target = .thinking
        } else if let lastMessageID = viewModel.messages.last?.id {
            target = .message(lastMessageID)
        } else {
            target = nil
        }

        guard let target else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    private var overlayShade: Color {
        colorScheme == .dark ? .black : .white
    }

    private var headerCapsuleBorder: Color {
        if viewModel.appTheme == .bubbleGum {
            return Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)
    }
}
