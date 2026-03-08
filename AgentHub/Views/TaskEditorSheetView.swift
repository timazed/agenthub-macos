import AppKit
import SwiftUI

struct TaskEditorSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft: TaskRecord
    @State private var intervalUnit: IntervalScheduleUnit
    private let isNew: Bool
    let onSave: (TaskRecord, Bool) -> Void
    let onCancel: () -> Void
    private let headerHeight: CGFloat = 86

    init(
        task: TaskRecord?,
        onSave: @escaping (TaskRecord, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let now = Date()
        let value = task ?? TaskRecord(
            id: UUID(),
            title: "",
            instructions: "",
            scheduleType: .manual,
            scheduleValue: "",
            state: .scheduled,
            codexThreadId: nil,
            personaId: "default",
            runtimeMode: .chatOnly,
            repoPath: nil,
            createdAt: now,
            updatedAt: now,
            lastRun: nil,
            nextRun: nil,
            lastError: nil
        )
        _draft = State(initialValue: value)
        _intervalUnit = State(initialValue: IntervalScheduleUnit.fromScheduleValue(value.scheduleType, value.scheduleValue))
        self.isNew = task == nil
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Background work stays attached to the assistant and runs with the default persona.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.9))

                    formCard

                    HStack {
                        Spacer()
                        Button("Cancel") {
                            onCancel()
                            dismiss()
                        }
                        .buttonStyle(.bordered)

                    Button("Save") {
                        onSave(normalizedDraft, isNew)
                        dismiss()
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.blue.opacity(0.9))
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, headerHeight + 20)
                .padding(.bottom, 28)
            }
        }
        .overlay(alignment: .top) {
            headerOverlay
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            labeledField("Title") {
                TextField("Bondi rental monitor", text: $draft.title)
            }

            labeledField("Instructions") {
                TextEditor(text: $draft.instructions)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
            }

            labeledField("Workspace Directory") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        TextField("Optional absolute path", text: Binding(
                            get: { draft.externalDirectoryPath ?? "" },
                            set: { draft.externalDirectoryPath = $0.isEmpty ? nil : $0 }
                        ))

                        Button("Choose…") {
                            if let path = pickDirectory() {
                                draft.externalDirectoryPath = path
                            }
                        }
                    }

                    Text("Leave this empty to run like a normal assistant task. Add a directory only when the task should work inside a specific workspace.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            scheduleSection
        }
        .textFieldStyle(.plain)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06), lineWidth: 1)
                )
        )
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Text("Schedule")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.94))

                Spacer()

                scheduleModePicker
            }

            switch draft.scheduleType {
            case .manual:
                manualSchedulePanel
            case .intervalMinutes:
                intervalSchedulePanel
            case .dailyAtHHMM:
                dailySchedulePanel
            }

            if let scheduleSummary {
                Label(scheduleSummary, systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.88))
            }
        }
    }

    private var headerOverlay: some View {
        VStack(spacing: 0) {
            Text(isNew ? "Add Task" : "Edit Task")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.96))
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 14)
                .background(
                    Rectangle()
                        .fill(.clear)
                        .liquidGlass()
                        .mask(
                            LinearGradient(
                                colors: [.black, .black.opacity(0.9), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )

            Spacer(minLength: 0)
        }
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(false)
    }

    private var scheduleModePicker: some View {
        HStack(spacing: 4) {
            ForEach(scheduleModes, id: \.self) { scheduleType in
                Button(scheduleTitle(for: scheduleType)) {
                    updateScheduleType(scheduleType)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .font(.system(size: 13, weight: .semibold))
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
        .background(scheduleControlBackground(cornerRadius: 20))
    }

    private var dailySchedulePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                DatePicker(
                    "",
                    selection: dailyTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.field)
                .font(.system(size: 14, weight: .semibold))

                Spacer(minLength: 0)

                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.84))
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .background(scheduleControlBackground(cornerRadius: 18))

            weekdayPills
        }
    }

    private var intervalSchedulePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text("Run every")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.92))

                TextField("24", text: intervalValueBinding)
                    .frame(width: 64)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 15, weight: .semibold))
                    .textFieldStyle(.plain)

                Picker("", selection: intervalUnitBinding) {
                    Text("Hours").tag(IntervalScheduleUnit.hours)
                    Text("Minutes").tag(IntervalScheduleUnit.minutes)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                .font(.system(size: 12, weight: .semibold))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .background(scheduleControlBackground(cornerRadius: 18))

            weekdayPills
        }
    }

    private var manualSchedulePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This task stays idle until you start it manually.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.92))

            Text("Switch to Daily or Interval when you want it to run on its own.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(0.86))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scheduleControlBackground(cornerRadius: 18))
    }

    private var weekdayPills: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 34, maximum: 34), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(TaskScheduleWeekday.allCases, id: \.self) { weekday in
                Button {
                    toggle(weekday: weekday)
                } label: {
                    Text(weekday.shortLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(weekdayTextColor(for: weekday))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(weekdayFillColor(for: weekday))
                                .overlay(
                                    Circle()
                                        .stroke(weekdayStrokeColor(for: weekday), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Select the days this task should run")
    }

    private var scheduleSummary: String? {
        switch draft.scheduleType {
        case .manual:
            return "Runs only when started manually."
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

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.92))
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(inputBackground)
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.05), lineWidth: 1)
            )
    }

    private func scheduleControlBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.03))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 1)
            )
    }

    private var backgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                .black,
                Color(red: 0.06, green: 0.06, blue: 0.07)
            ]
        }
        return [
            .white,
            Color(red: 0.96, green: 0.97, blue: 0.99)
        ]
    }

    private func pickDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private var scheduleModes: [TaskScheduleType] {
        [.manual, .dailyAtHHMM, .intervalMinutes]
    }

    private var scheduleConfig: TaskScheduleConfiguration {
        TaskScheduleConfiguration(scheduleType: draft.scheduleType, scheduleValue: draft.scheduleValue)
    }

    private var intervalMinutes: Int? {
        scheduleConfig.intervalMinutes
    }

    private var nextRunDate: Date? {
        scheduleConfig.nextRun(after: Date())
    }

    private var parsedDailyTime: Date? {
        guard let dailyTime = scheduleConfig.dailyTime else {
            return nil
        }
        return Calendar.current.date(bySettingHour: dailyTime.hour, minute: dailyTime.minute, second: 0, of: Date())
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

    private var intervalUnitBinding: Binding<IntervalScheduleUnit> {
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

    private func weekdayFillColor(for weekday: TaskScheduleWeekday) -> Color {
        if isWeekdaySelected(weekday) {
            return Color.white.opacity(colorScheme == .dark ? 0.96 : 0.92)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.03)
    }

    private func weekdayStrokeColor(for weekday: TaskScheduleWeekday) -> Color {
        if isWeekdaySelected(weekday) {
            return Color.black.opacity(colorScheme == .dark ? 0.06 : 0.08)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.07)
    }

    private func weekdayTextColor(for weekday: TaskScheduleWeekday) -> Color {
        if isWeekdaySelected(weekday) {
            return Color.black.opacity(0.8)
        }
        return Color.primary.opacity(0.78)
    }

    private func scheduleTitle(for scheduleType: TaskScheduleType) -> String {
        switch scheduleType {
        case .manual:
            return "Manual"
        case .dailyAtHHMM:
            return "Daily"
        case .intervalMinutes:
            return "Interval"
        }
    }

    private var normalizedDraft: TaskRecord {
        var task = draft
        task.runtimeMode = task.externalDirectoryPath?.isEmpty == false ? .task : .chatOnly
        return task
    }
}

private enum IntervalScheduleUnit: String, CaseIterable, Hashable {
    case hours
    case minutes

    static func fromScheduleValue(_ scheduleType: TaskScheduleType, _ value: String) -> IntervalScheduleUnit {
        let config = TaskScheduleConfiguration(scheduleType: scheduleType, scheduleValue: value)
        guard let minutes = config.intervalMinutes, minutes > 0 else { return .hours }
        return minutes % 60 == 0 ? .hours : .minutes
    }
}
