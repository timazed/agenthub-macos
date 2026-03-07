import SwiftUI
import AppKit

struct ChatView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var viewModel: ChatViewModel
    let isPanelPresented: Bool
    let onTogglePanel: () -> Void

    @State private var composerHeight: CGFloat = ComposerMetrics.minTextHeight

    private let topOverlayHeight: CGFloat = 100
    private let bottomOverlayHeight: CGFloat = 120

    var body: some View {
        ZStack {
            conversationSurface
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: backgroundGradientColors,
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
                                .id(ConversationScrollTarget.message(message.id))
                        case .thinking:
                            ConversationThinkingRow()
                                .id(ConversationScrollTarget.thinking)
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
            .onChange(of: viewModel.isBusy) { _, _ in
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
                .background(
                    Rectangle()
                        .fill(.clear)
                        .liquidGlass()
                        .mask(
                            LinearGradient(
                                colors: [.black, .black.opacity(0.82), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )

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
        .background(
            LinearGradient(
                colors: [Color.clear, overlayShade.opacity(colorScheme == .dark ? 0.44 : 0.12)],
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
                                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
                            )
                    )

                    HStack(spacing: 6) {
                        Text(viewModel.runtimeDescriptor)
                            .font(.caption)
                            .foregroundStyle(Color.secondary.opacity(0.9))
                    }
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
                HStack(alignment: .center, spacing: 8) {
                    ComposerTextView(
                        text: $viewModel.inputText,
                        calculatedHeight: $composerHeight,
                        placeholder: "Ask me to do anything (one off or repeatable)",
                        colorScheme: colorScheme,
                        isEnabled: !viewModel.isBusy,
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
                        systemName: viewModel.isBusy ? "stop.fill" : "arrow.up",
                        diameter: ComposerMetrics.controlHeight
                    ) {
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

        if viewModel.isBusy {
            entries.append(.init(kind: .thinking))
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
        let target: ConversationScrollTarget?
        if viewModel.isBusy {
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

    private var backgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                .black,
                Color(red: 0.04, green: 0.05, blue: 0.08),
                .black
            ]
        }
        return [
            .white,
            Color(red: 0.95, green: 0.97, blue: 1.0),
            .white
        ]
    }

    private var overlayShade: Color {
        colorScheme == .dark ? .black : .white
    }
}

private struct AgentAvatarView: View {
    let name: String
    let profilePictureURL: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.41, green: 0.34, blue: 0.76), Color(red: 0.17, green: 0.18, blue: 0.24)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(initial)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.96))
        }
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let character = trimmed.first else { return "A" }
        return String(character).uppercased()
    }

    private var imageURL: URL? {
        guard let profilePictureURL else { return nil }
        let trimmed = profilePictureURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}

private enum ConversationScrollTarget: Hashable {
    case message(UUID)
    case thinking
}

private struct ConversationEntry: Identifiable {
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

private struct DateSeparator: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String

    var body: some View {
        Text(label)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.secondary.opacity(colorScheme == .dark ? 0.8 : 0.9))
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
    }
}

private struct ConversationBubble: View {
    @Environment(\.colorScheme) private var colorScheme
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
                            .stroke(Color.primary.opacity(isIncoming ? (colorScheme == .dark ? 0.06 : 0.08) : 0.0), lineWidth: 1)
                    )
            )
    }

    private var isIncoming: Bool {
        message.role != .user
    }

    private var textColor: Color {
        isIncoming ? Color.primary.opacity(0.92) : .white
    }

    private var bubbleFill: some ShapeStyle {
        if isIncoming {
            return AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
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

private struct ConversationThinkingRow: View {
    var body: some View {
        HStack {
            ThinkingStatusText()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CircleIconButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemName: String
    let diameter: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.92 : 0.82))
                .frame(width: diameter, height: diameter)
                .liquidGlass()
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct ThinkingStatusText: View {
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

private struct PendingTaskProposalCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft: TaskProposal
    @State private var intervalUnit: InlineIntervalScheduleUnit
    let onConfirm: (TaskProposal) -> Void
    let onCancel: () -> Void

    init(proposal: TaskProposal, onConfirm: @escaping (TaskProposal) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: proposal)
        _intervalUnit = State(initialValue: InlineIntervalScheduleUnit.fromScheduleValue(proposal.scheduleType, proposal.scheduleValue))
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Task Proposal", systemImage: "clock.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.88))
                Spacer()
            }

            Text(draft.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.94))

            Text(draft.instructions)
                .font(.callout)
                .foregroundStyle(Color.secondary.opacity(0.92))

            inlineScheduleSection

            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Create Task") {
                    onConfirm(normalizedProposal)
                }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.blue.opacity(0.9))
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.clear)
                .liquidGlass(cornerRadius: 18)
        )
    }

    private var inlineScheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Schedule")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.92))

                Spacer()

                HStack(spacing: 4) {
                    ForEach(inlineScheduleModes, id: \.self) { scheduleType in
                        Button(inlineScheduleTitle(for: scheduleType)) {
                            updateScheduleType(scheduleType)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(scheduleType == draft.scheduleType ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08) : .clear)
                        )
                        .foregroundStyle(
                            scheduleType == draft.scheduleType
                            ? Color.primary.opacity(0.94)
                            : Color.secondary.opacity(0.82)
                        )
                    }
                }
                .padding(4)
                .background(inlineControlBackground(cornerRadius: 18))
            }

            switch draft.scheduleType {
            case .manual:
                inlineManualPanel
            case .dailyAtHHMM:
                inlineDailyPanel
            case .intervalMinutes:
                inlineIntervalPanel
            }

            if let summary = inlineScheduleSummary {
                Text(summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.84))
            }
        }
    }

    private var inlineDailyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DatePicker(
                    "",
                    selection: dailyTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.field)
                .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 0)

                Image(systemName: "clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.84))
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(inlineControlBackground(cornerRadius: 16))

            inlineWeekdayPills
        }
    }

    private var inlineIntervalPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Run every")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.9))

                TextField("24", text: intervalValueBinding)
                    .frame(width: 56)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 14, weight: .semibold))
                    .textFieldStyle(.plain)

                Picker("", selection: intervalUnitBinding) {
                    Text("Hours").tag(InlineIntervalScheduleUnit.hours)
                    Text("Minutes").tag(InlineIntervalScheduleUnit.minutes)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 170)
                .font(.system(size: 11, weight: .semibold))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(inlineControlBackground(cornerRadius: 16))

            inlineWeekdayPills
        }
    }

    private var inlineManualPanel: some View {
        Text("Runs only when started manually.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.secondary.opacity(0.84))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(inlineControlBackground(cornerRadius: 16))
    }

    private var inlineWeekdayPills: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(TaskScheduleWeekday.allCases, id: \.self) { weekday in
                Button {
                    toggle(weekday: weekday)
                } label: {
                    Text(weekday.shortLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(inlineWeekdayTextColor(for: weekday))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(inlineWeekdayFillColor(for: weekday))
                                .overlay(
                                    Circle()
                                        .stroke(inlineWeekdayStrokeColor(for: weekday), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func inlineControlBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.04))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 1)
            )
    }

    private var scheduleConfig: TaskScheduleConfiguration {
        TaskScheduleConfiguration(scheduleType: draft.scheduleType, scheduleValue: draft.scheduleValue)
    }

    private var normalizedProposal: TaskProposal {
        var proposal = draft
        proposal.runtimeMode = proposal.externalDirectoryPath?.isEmpty == false ? .task : .chatOnly
        return proposal
    }

    private var intervalMinutes: Int? {
        scheduleConfig.intervalMinutes
    }

    private var parsedDailyTime: Date? {
        guard let dailyTime = scheduleConfig.dailyTime else { return nil }
        return Calendar.current.date(bySettingHour: dailyTime.hour, minute: dailyTime.minute, second: 0, of: Date())
    }

    private var nextRunDate: Date? {
        scheduleConfig.nextRun(after: Date())
    }

    private var inlineScheduleSummary: String? {
        switch draft.scheduleType {
        case .manual:
            return "Manual run only."
        case .dailyAtHHMM:
            guard let nextRun = nextRunDate else { return "Choose a daily run time." }
            return "\(weekdaySummary). Next run \(nextRun.formatted(date: .abbreviated, time: .shortened))."
        case .intervalMinutes:
            guard let minutes = intervalMinutes else { return "Enter how often this task should run." }
            let valueText: String
            if intervalUnit == .hours && minutes % 60 == 0 {
                let hours = max(1, minutes / 60)
                valueText = "\(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                valueText = "\(minutes) minute\(minutes == 1 ? "" : "s")"
            }
            guard let nextRun = nextRunDate else { return "Runs every \(valueText) on \(selectedWeekdayList)." }
            return "Runs every \(valueText) on \(selectedWeekdayList). Next run \(nextRun.formatted(date: .abbreviated, time: .shortened))."
        }
    }

    private var dailyTimeBinding: Binding<Date> {
        Binding(
            get: {
                parsedDailyTime
                ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
                ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                updateScheduleValue(baseValue: String(format: "%02d:%02d", components.hour ?? 9, components.minute ?? 0))
            }
        )
    }

    private var intervalValueBinding: Binding<String> {
        Binding(
            get: {
                let minutes = intervalMinutes ?? defaultIntervalMinutes
                switch intervalUnit {
                case .hours:
                    return String(max(1, Int((Double(minutes) / 60.0).rounded())))
                case .minutes:
                    return String(minutes)
                }
            },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                guard let value = Int(digits), value > 0 else {
                    updateScheduleValue(baseValue: "")
                    return
                }
                switch intervalUnit {
                case .hours:
                    updateScheduleValue(baseValue: String(max(1, value) * 60))
                case .minutes:
                    updateScheduleValue(baseValue: String(max(1, value)))
                }
            }
        )
    }

    private var intervalUnitBinding: Binding<InlineIntervalScheduleUnit> {
        Binding(
            get: { intervalUnit },
            set: { newValue in
                let minutes = intervalMinutes ?? defaultIntervalMinutes
                intervalUnit = newValue
                switch newValue {
                case .hours:
                    let normalizedHours = max(1, Int((Double(minutes) / 60.0).rounded()))
                    updateScheduleValue(baseValue: String(normalizedHours * 60))
                case .minutes:
                    updateScheduleValue(baseValue: String(max(1, minutes)))
                }
            }
        )
    }

    private var defaultIntervalMinutes: Int {
        intervalUnit == .hours ? 24 * 60 : 60
    }

    private var inlineScheduleModes: [TaskScheduleType] {
        [.manual, .dailyAtHHMM, .intervalMinutes]
    }

    private func inlineScheduleTitle(for scheduleType: TaskScheduleType) -> String {
        switch scheduleType {
        case .manual:
            return "Manual"
        case .dailyAtHHMM:
            return "Daily"
        case .intervalMinutes:
            return "Interval"
        }
    }

    private func updateScheduleType(_ newValue: TaskScheduleType) {
        draft.scheduleType = newValue
        switch newValue {
        case .manual:
            break
        case .dailyAtHHMM:
            if parsedDailyTime == nil {
                updateScheduleValue(baseValue: "09:00")
            }
        case .intervalMinutes:
            let minutes = intervalMinutes ?? 24 * 60
            intervalUnit = minutes % 60 == 0 ? .hours : .minutes
            updateScheduleValue(baseValue: String(minutes))
        }
    }

    private func updateScheduleValue(baseValue: String) {
        draft.scheduleValue = TaskScheduleConfiguration(
            scheduleType: draft.scheduleType,
            baseValue: baseValue,
            weekdays: scheduleConfig.weekdays
        ).scheduleValue
    }

    private func toggle(weekday: TaskScheduleWeekday) {
        var weekdays = scheduleConfig.weekdays
        if weekdays.contains(weekday) {
            weekdays.remove(weekday)
        } else {
            weekdays.insert(weekday)
        }

        draft.scheduleValue = TaskScheduleConfiguration(
            scheduleType: draft.scheduleType,
            baseValue: scheduleConfig.baseValue,
            weekdays: weekdays
        ).scheduleValue
    }

    private func isWeekdaySelected(_ weekday: TaskScheduleWeekday) -> Bool {
        scheduleConfig.weekdays.contains(weekday)
    }

    private func inlineWeekdayFillColor(for weekday: TaskScheduleWeekday) -> Color {
        if isWeekdaySelected(weekday) {
            return Color.white.opacity(colorScheme == .dark ? 0.96 : 0.92)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.03)
    }

    private func inlineWeekdayStrokeColor(for weekday: TaskScheduleWeekday) -> Color {
        if isWeekdaySelected(weekday) {
            return Color.black.opacity(colorScheme == .dark ? 0.06 : 0.08)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.07)
    }

    private func inlineWeekdayTextColor(for weekday: TaskScheduleWeekday) -> Color {
        if isWeekdaySelected(weekday) {
            return Color.black.opacity(0.8)
        }
        return Color.primary.opacity(0.78)
    }

    private var selectedWeekdayList: String {
        let weekdays = TaskScheduleWeekday.allCases.filter { scheduleConfig.weekdays.contains($0) }
        if weekdays.isEmpty {
            return "no days selected"
        }
        if weekdays.count == TaskScheduleWeekday.allCases.count {
            return "every day"
        }
        return weekdays.map(\.shortLabel).joined(separator: ", ")
    }

    private var weekdaySummary: String {
        if scheduleConfig.weekdays.isEmpty {
            return "No active days selected"
        }
        if scheduleConfig.runsEveryDay {
            return "Runs every day"
        }
        return "Runs on \(selectedWeekdayList)"
    }
}

private enum InlineIntervalScheduleUnit: String, CaseIterable, Hashable {
    case hours
    case minutes

    static func fromScheduleValue(_ scheduleType: TaskScheduleType, _ value: String) -> InlineIntervalScheduleUnit {
        let config = TaskScheduleConfiguration(scheduleType: scheduleType, scheduleValue: value)
        guard let minutes = config.intervalMinutes, minutes > 0 else { return .hours }
        return minutes % 60 == 0 ? .hours : .minutes
    }
}

private struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var calculatedHeight: CGFloat
    let placeholder: String
    let colorScheme: ColorScheme
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
        textView.minSize = NSSize(width: 0, height: ComposerMetrics.minTextHeight)
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.placeholderColor = placeholderColor
        textView.placeholder = placeholder
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
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.placeholderColor = placeholderColor
        textView.placeholder = placeholder
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.invalidateIntrinsicContentSize()
        context.coordinator.recalculateHeight(for: textView)
    }

    private var textColor: NSColor {
        colorScheme == .dark ? NSColor.white.withAlphaComponent(0.94) : NSColor.black.withAlphaComponent(0.88)
    }

    private var placeholderColor: NSColor {
        colorScheme == .dark ? NSColor.white.withAlphaComponent(0.36) : NSColor.black.withAlphaComponent(0.32)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, SubmitTextViewDelegate {
        @Binding private var text: String
        @Binding private var calculatedHeight: CGFloat
        let onSubmit: () -> Void
        weak var textView: SubmitTextView?

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
            if textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if calculatedHeight != ComposerMetrics.minTextHeight {
                    DispatchQueue.main.async {
                        self.calculatedHeight = ComposerMetrics.minTextHeight
                    }
                }
                return
            }

            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let height = max(
                ComposerMetrics.minTextHeight,
                min(ComposerMetrics.maxTextHeight, ceil(usedRect.height + textView.textContainerInset.height * 2))
            )
            if calculatedHeight != height {
                DispatchQueue.main.async {
                    self.calculatedHeight = height
                }
            }
        }
    }
}

private enum ComposerMetrics {
    static let controlHeight: CGFloat = 38
    static let verticalPadding: CGFloat = 7
    static let minTextHeight: CGFloat = controlHeight - (verticalPadding * 2)
    static let maxTextHeight: CGFloat = 92
}

private protocol SubmitTextViewDelegate: AnyObject {
    func submitTextViewDidRequestSubmit(_ textView: SubmitTextView)
}

private final class SubmitTextView: NSTextView {
    weak var submitDelegate: SubmitTextViewDelegate?
    var placeholder: String = "" {
        didSet {
            needsDisplay = true
        }
    }
    var placeholderColor: NSColor = NSColor.placeholderTextColor {
        didSet {
            needsDisplay = true
        }
    }

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

    override var string: String {
        didSet {
            needsDisplay = true
        }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholder.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: placeholderColor
        ]
        let linePadding = textContainer?.lineFragmentPadding ?? 0
        let origin = NSPoint(x: textContainerInset.width + linePadding, y: textContainerInset.height)
        placeholder.draw(at: origin, withAttributes: attributes)
    }
}
