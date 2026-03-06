import SwiftUI
import AppKit

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    let isPanelPresented: Bool
    let onTogglePanel: () -> Void

    @State private var composerHeight: CGFloat = 22

    private let topOverlayHeight: CGFloat = 128
    private let bottomOverlayHeight: CGFloat = 120

    var body: some View {
        ZStack {
            conversationSurface
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.96),
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color.black.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            headerOverlay
        }
        .overlay(alignment: .bottom) {
            composerOverlay
        }
    }

    private var conversationSurface: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 18) {
                    ForEach(groupedEntries) { entry in
                        switch entry.kind {
                        case let .separator(label):
                            DateSeparator(label: label)
                        case let .message(message):
                            ConversationBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, topOverlayHeight)
                .padding(.bottom, bottomOverlayHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentMargins(.top, 0, for: .scrollContent)
            .contentMargins(.bottom, 0, for: .scrollContent)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
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
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.36), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: topOverlayHeight)
            .frame(maxHeight: .infinity, alignment: .top)
        )
    }

    private var composerOverlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            composer
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
        }
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.44)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: bottomOverlayHeight)
            .frame(maxHeight: .infinity, alignment: .bottom)
        )
    }

    private var header: some View {
        VStack(spacing: 6) {
            Button(action: onTogglePanel) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.41, green: 0.34, blue: 0.76), Color(red: 0.17, green: 0.18, blue: 0.24)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)
                            .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 5)

                        Text("A")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.96))
                    }

                    HStack(spacing: 8) {
                        Text("AgentHub")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.96))

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )

                    Text(viewModel.runtimeDescriptor)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.48))

                    if viewModel.isBusy {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white.opacity(0.8))
                            Text("Thinking")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.54))
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let proposal = viewModel.pendingProposal {
                PendingTaskProposalCard(
                    proposal: proposal,
                    onConfirm: { viewModel.confirmPendingProposal() },
                    onDismiss: { viewModel.dismissPendingProposal() }
                )
            }

            HStack(alignment: .bottom, spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    ComposerTextView(
                        text: $viewModel.inputText,
                        calculatedHeight: $composerHeight,
                        isEnabled: !viewModel.isBusy,
                        onSubmit: { viewModel.sendCurrentInput() }
                    )
                    .frame(height: composerHeight)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(.clear)
                        .liquidGlass(cornerRadius: 20)
                )

                HStack(spacing: 8) {
                    CircleIconButton(systemName: viewModel.isBusy ? "stop.fill" : "arrow.up") {
                        if viewModel.isBusy {
                            viewModel.cancel()
                        } else {
                            viewModel.sendCurrentInput()
                        }
                    }
                    .disabled(!viewModel.isBusy && viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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

        return entries
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
        guard let lastID = viewModel.messages.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

private struct ConversationEntry: Identifiable {
    enum Kind {
        case separator(String)
        case message(Message)
    }

    let id = UUID()
    let kind: Kind
}

private struct DateSeparator: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white.opacity(0.36))
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
    }
}

private struct ConversationBubble: View {
    let message: Message

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
        Text(message.text)
            .textSelection(.enabled)
            .font(.body)
            .foregroundStyle(textColor)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                bubbleShape
                    .fill(bubbleFill)
                    .overlay(
                        bubbleShape
                            .stroke(Color.white.opacity(isIncoming ? 0.04 : 0.0), lineWidth: 1)
                    )
            )
    }

    private var isIncoming: Bool {
        message.role != .user
    }

    private var textColor: Color {
        isIncoming ? .white.opacity(0.92) : .white
    }

    private var bubbleFill: some ShapeStyle {
        if isIncoming {
            return AnyShapeStyle(Color.white.opacity(0.14))
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [Color.blue.opacity(0.92), Color.cyan.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }
}

private struct CircleIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 32, height: 32)
                .liquidGlass()
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct PendingTaskProposalCard: View {
    let proposal: TaskProposal
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Task Proposal", systemImage: "clock.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.45))
            }

            Text(proposal.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.94))

            Text(proposal.instructions)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.62))

            HStack(spacing: 8) {
                ProposalChip(label: "Schedule", value: proposal.scheduleType.rawValue)
                ProposalChip(label: "Mode", value: proposal.runtimeMode.rawValue)
            }

            Button("Create Task", action: onConfirm)
                .buttonStyle(.borderedProminent)
                .tint(Color.blue.opacity(0.9))
                .controlSize(.small)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct ProposalChip: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .foregroundStyle(.white.opacity(0.82))
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var calculatedHeight: CGFloat
    let isEnabled: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, calculatedHeight: $calculatedHeight, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = SubmitTextView()
        textView.delegate = context.coordinator
        textView.submitDelegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = NSColor.white.withAlphaComponent(0.94)
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.recalculateHeight(for: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEnabled
        textView.isSelectable = true
        context.coordinator.recalculateHeight(for: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, SubmitTextViewDelegate {
        @Binding private var text: String
        @Binding private var calculatedHeight: CGFloat
        let onSubmit: () -> Void
        weak var textView: NSTextView?

        init(text: Binding<String>, calculatedHeight: Binding<CGFloat>, onSubmit: @escaping () -> Void) {
            _text = text
            _calculatedHeight = calculatedHeight
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            recalculateHeight(for: textView)
        }

        func submitTextViewDidRequestSubmit(_ textView: SubmitTextView) {
            let trimmed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onSubmit()
        }

        func recalculateHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let height = max(22, min(92, ceil(usedRect.height + textView.textContainerInset.height * 2)))
            if calculatedHeight != height {
                DispatchQueue.main.async {
                    self.calculatedHeight = height
                }
            }
        }
    }
}

private protocol SubmitTextViewDelegate: AnyObject {
    func submitTextViewDidRequestSubmit(_ textView: SubmitTextView)
}

private final class SubmitTextView: NSTextView {
    weak var submitDelegate: SubmitTextViewDelegate?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
                super.keyDown(with: event)
            } else {
                submitDelegate?.submitTextViewDidRequestSubmit(self)
            }
            return
        }
        super.keyDown(with: event)
    }
}
