import SwiftUI
import AppKit

struct CircleIconButton: View {
    let systemName: String
    let diameter: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CircleGlassButton(diameter: diameter) {
                Image(systemName: systemName)
                    .font(.body.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
    }
}

struct BrainMenuButton: View {
    let diameter: CGFloat

    var body: some View {
        CircleIconLabelButton(label: "🧠", diameter: diameter)
    }
}

struct ReasoningMenuButton: View {
    let diameter: CGFloat

    var body: some View {
        CircleIconLabelButton(label: "🤔", diameter: diameter)
    }
}

struct CircleIconLabelButton: View {
    let label: String
    let diameter: CGFloat

    var body: some View {
        CircleGlassButton(diameter: diameter) {
            Text(label)
                .font(.system(size: 20))
        }
    }
}

struct CircleGlassButton<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let diameter: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.92 : 0.82))
            .frame(width: diameter, height: diameter)
            .background {
                if #available(macOS 26.0, iOS 26.0, *) {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.regular, in: .circle)
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18), lineWidth: 1)
            }
            .clipShape(Circle())
    }
}

struct ModelPickerPopover: View {
    let models: [SupportedModel]
    let activeModel: String
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Switch Model")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .padding(.bottom, 4)

            ForEach(models) { model in
                Button {
                    onSelect(model.id)
                } label: {
                    PickerOptionRow(isSelected: model.id == activeModel) {
                        Text(model.displayName)
                            .font(.body)
                    } trailing: {
                        if model.id == activeModel {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}

struct ReasoningPickerPopover: View {
    let activeReasoning: String
    let onSelect: (ReasoningEffort) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reasoning")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .padding(.bottom, 4)

            ForEach(ReasoningEffort.allCases, id: \.self) { reasoning in
                Button {
                    onSelect(reasoning)
                } label: {
                    PickerOptionRow(isSelected: reasoning.displayName == activeReasoning) {
                        Text(reasoning.displayName)
                            .font(.body)
                    } trailing: {
                        if reasoning.displayName == activeReasoning {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}

struct PickerOptionRow<Leading: View, Trailing: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    let isSelected: Bool
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            leading()
            Spacer(minLength: 16)
            trailing()
        }
        .foregroundStyle(Color.primary.opacity(0.92))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundColor: Color {
        if isHovered {
            return Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.12)
        }
        if isSelected {
            return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08)
        }
        return .clear
    }
}

struct PendingTaskProposalCard: View {
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

enum InlineIntervalScheduleUnit: String, CaseIterable, Hashable {
    case hours
    case minutes

    static func fromScheduleValue(_ scheduleType: TaskScheduleType, _ value: String) -> InlineIntervalScheduleUnit {
        let config = TaskScheduleConfiguration(scheduleType: scheduleType, scheduleValue: value)
        guard let minutes = config.intervalMinutes, minutes > 0 else { return .hours }
        return minutes % 60 == 0 ? .hours : .minutes
    }
}

struct ComposerTextView: NSViewRepresentable {
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

enum ComposerMetrics {
    static let controlHeight: CGFloat = 38
    static let verticalPadding: CGFloat = 7
    static let minTextHeight: CGFloat = controlHeight - (verticalPadding * 2)
    static let maxTextHeight: CGFloat = 92
}

protocol SubmitTextViewDelegate: AnyObject {
    func submitTextViewDidRequestSubmit(_ textView: SubmitTextView)
}

final class SubmitTextView: NSTextView {
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
