import SwiftUI

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
    @StateObject private var headerSnapshotStore = HeaderSnapshotStore()
    @State private var isHeaderScrollActive = false
    @State private var isHeaderBlurVisible = true
    @State private var scrollSettledWorkItem: DispatchWorkItem?
    @State private var snapshotRefreshToken = 0

    private let topOverlayHeight: CGFloat = 56
    private let bottomOverlayHeight: CGFloat = 120
    private let headerBackdropHeight: CGFloat = 100

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: viewModel.appTheme != .bubbleGum)) { timeline in
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    chatScene(size: proxy.size, timelineDate: timeline.date)
                    headerBackdrop(size: proxy.size)
                    headerOverlay
                    composerOverlay
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.clear)
            }
        }
    }

    @ViewBuilder
    private func chatScene(size: CGSize, timelineDate: Date) -> some View {
        ZStack {
            themeBackground(timelineDate: timelineDate)
            conversationSurface
        }
        .background(ChatSceneSnapshotSourceObserver(store: headerSnapshotStore))
        .frame(width: size.width, height: size.height)
        .background(.clear)
    }

    private var conversationSurface: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                conversationEntriesStack(useLazyLayout: true, includeScrollTargets: true, displayMode: .live)
                    .padding(.horizontal, 32)
                    .padding(.top, topOverlayHeight)
                    .padding(.bottom, bottomOverlayHeight)
            }
            .background(.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ScrollActivityObserver { velocity in
                    noteScrollActivity(velocity: velocity)
                } onScrollEnded: {
                    noteScrollEnded()
                } onScrollViewResolved: { scrollView in
                    if headerSnapshotStore.scrollView !== scrollView {
                        headerSnapshotStore.scrollView = scrollView
                        snapshotRefreshToken &+= 1
                    }
                }
            )
            .contentMargins(.top, 0, for: .scrollContent)
            .contentMargins(.bottom, 0, for: .scrollContent)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
                refreshHeaderSnapshotSoon()
            }
            .onChange(of: viewModel.isThinking) { _, _ in
                scrollToBottom(proxy: proxy)
                refreshHeaderSnapshotSoon()
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
                refreshHeaderSnapshotSoon()
            }
        }
    }

    private func headerBackdrop(size: CGSize) -> some View {
        ZStack(alignment: .top) {
            HeaderSnapshotSurfaceView(
                store: headerSnapshotStore,
                width: size.width,
                headerHeight: headerBackdropHeight,
                refreshID: snapshotRefreshID,
                isLiveCaptureEnabled: headerSnapshotShouldRunLive
            )
            .frame(
                width: size.width,
                height: headerBackdropHeight,
                alignment: .top
            )
            .opacity(isHeaderBlurVisible ? 1 : 0)
        }
        .frame(width: size.width, height: headerBackdropHeight, alignment: .top)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0.0),
                    .init(color: .white, location: 0.72),
                    .init(color: .white.opacity(0.75), location: 0.86),
                    .init(color: .white.opacity(0.28), location: 0.95),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .animation(.easeOut(duration: 0.18), value: isHeaderScrollActive)
        .animation(.easeOut(duration: 0.18), value: isHeaderBlurVisible)
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(false)
    }

    private func noteScrollActivity(velocity: CGFloat) {
        isHeaderScrollActive = true
        isHeaderBlurVisible = false

        scrollSettledWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            isHeaderScrollActive = false
            DispatchQueue.main.async {
                snapshotRefreshToken &+= 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard !isHeaderScrollActive else { return }
                isHeaderBlurVisible = true
            }
        }
        scrollSettledWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }

    private func noteScrollEnded() {
        scrollSettledWorkItem?.cancel()
        isHeaderScrollActive = false
        isHeaderBlurVisible = false
        DispatchQueue.main.async {
            snapshotRefreshToken &+= 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard !isHeaderScrollActive else { return }
            isHeaderBlurVisible = true
        }
    }

    private var snapshotRefreshID: Int { snapshotRefreshToken }

    private var headerSnapshotShouldRunLive: Bool {
        viewModel.appTheme == .bubbleGum && isHeaderBlurVisible && !isHeaderScrollActive
    }

    private func refreshHeaderSnapshotSoon() {
        guard !isHeaderScrollActive else { return }
        DispatchQueue.main.async {
            snapshotRefreshToken &+= 1
        }
    }

    private var headerOverlay: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(true)
    }

    private var composerOverlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            composer
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
        }
        .background(.clear)
    }

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
                        .shadow(color: overlayShade.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 10, x: 0, y: 5)
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
                    .background(
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(headerCapsuleBorder, lineWidth: 1)
                            )
                    )
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }

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
                .popover(isPresented: $isModelMenuPresented, attachmentAnchor: .point(.trailing), arrowEdge: .trailing) {
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
                .popover(isPresented: $isReasoningMenuPresented, attachmentAnchor: .point(.trailing), arrowEdge: .trailing) {
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
                .background(
                    Capsule(style: .continuous)
                        .fill(.clear)
                        .liquidGlass(cornerRadius: 20)
                )

                HStack(spacing: 8) {
                    CircleIconButton(
                        systemName: viewModel.isThinking ? "stop.fill" : "arrow.up",
                        diameter: ComposerMetrics.controlHeight
                    ) {
                        if viewModel.isBusy {
                            viewModel.cancel()
                        } else {
                            viewModel.sendCurrentInput()
                        }
                    }
                    .disabled(
                        !isInputEnabled ||
                        viewModel.isExternalRunActive ||
                        (!viewModel.isBusy && viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
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
                    conversationEntry(entry, includeScrollTargets: includeScrollTargets, displayMode: displayMode)
                }
            }
        } else {
            VStack(spacing: 18) {
                ForEach(groupedEntries) { entry in
                    conversationEntry(entry, includeScrollTargets: includeScrollTargets, displayMode: displayMode)
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
                ConversationBubble(message: message, theme: viewModel.appTheme, displayMode: displayMode)
                    .id(ConversationScrollTarget.message(message.id))
            } else {
                ConversationBubble(message: message, theme: viewModel.appTheme, displayMode: displayMode)
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
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
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

    private var headerBackdropVeil: some ShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.black.opacity(viewModel.appTheme == .bubbleGum ? 0.44 : 0.52),
                        Color.black.opacity(viewModel.appTheme == .bubbleGum ? 0.24 : 0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color.white.opacity(viewModel.appTheme == .bubbleGum ? 0.26 : 0.32),
                    Color.white.opacity(viewModel.appTheme == .bubbleGum ? 0.12 : 0.16)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var headerMotionGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.black.opacity(viewModel.appTheme == .bubbleGum ? 0.72 : 0.8),
                    Color.black.opacity(viewModel.appTheme == .bubbleGum ? 0.46 : 0.58),
                    Color.black.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(viewModel.appTheme == .bubbleGum ? 0.5 : 0.64),
                Color.white.opacity(viewModel.appTheme == .bubbleGum ? 0.26 : 0.34),
                Color.white.opacity(0.04)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
