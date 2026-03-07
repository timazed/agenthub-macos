import Foundation

enum TaskScheduleWeekday: String, CaseIterable, Codable, Hashable {
    case mo
    case tu
    case we
    case th
    case fr
    case sa
    case su

    var shortLabel: String {
        rawValue.capitalized
    }

    var calendarWeekday: Int {
        switch self {
        case .su:
            return 1
        case .mo:
            return 2
        case .tu:
            return 3
        case .we:
            return 4
        case .th:
            return 5
        case .fr:
            return 6
        case .sa:
            return 7
        }
    }

    init?(calendarWeekday: Int) {
        switch calendarWeekday {
        case 1:
            self = .su
        case 2:
            self = .mo
        case 3:
            self = .tu
        case 4:
            self = .we
        case 5:
            self = .th
        case 6:
            self = .fr
        case 7:
            self = .sa
        default:
            return nil
        }
    }
}

struct TaskScheduleConfiguration: Equatable, Hashable {
    static let everyDay = Set(TaskScheduleWeekday.allCases)

    var scheduleType: TaskScheduleType
    var baseValue: String
    var weekdays: Set<TaskScheduleWeekday>

    init(
        scheduleType: TaskScheduleType,
        baseValue: String,
        weekdays: Set<TaskScheduleWeekday> = TaskScheduleConfiguration.everyDay
    ) {
        self.scheduleType = scheduleType
        self.baseValue = baseValue
        self.weekdays = weekdays
    }

    init(scheduleType: TaskScheduleType, scheduleValue: String) {
        let components = scheduleValue.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let baseValue = components.first.map(String.init) ?? ""
        let weekdays: Set<TaskScheduleWeekday>

        if components.count == 2 {
            let parsed = Set(
                components[1]
                    .split(separator: ",")
                    .compactMap { TaskScheduleWeekday(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
            )
            weekdays = parsed
        } else {
            weekdays = TaskScheduleConfiguration.everyDay
        }

        self.init(scheduleType: scheduleType, baseValue: baseValue, weekdays: weekdays)
    }

    var scheduleValue: String {
        guard scheduleType != .manual else { return baseValue }
        guard weekdays != Self.everyDay else { return baseValue }
        let orderedDays = TaskScheduleWeekday.allCases
            .filter { weekdays.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
        return "\(baseValue)|\(orderedDays)"
    }

    var runsEveryDay: Bool {
        weekdays == Self.everyDay
    }

    var hasActiveDays: Bool {
        !weekdays.isEmpty
    }

    var intervalMinutes: Int? {
        let value = Int(baseValue.filter(\.isNumber)) ?? 0
        return value > 0 ? value : nil
    }

    var dailyTime: (hour: Int, minute: Int)? {
        let parts = baseValue.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return (hour, minute)
    }

    func includes(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let weekday = TaskScheduleWeekday(calendarWeekday: calendar.component(.weekday, from: date)) else {
            return false
        }
        return weekdays.contains(weekday)
    }

    func nextRun(after now: Date, calendar: Calendar = .current) -> Date? {
        switch scheduleType {
        case .manual:
            return nil
        case .intervalMinutes:
            guard hasActiveDays, let minutes = intervalMinutes,
                  let candidate = calendar.date(byAdding: .minute, value: minutes, to: now) else {
                return nil
            }
            return nextAllowedDate(onOrAfter: candidate, calendar: calendar)
        case .dailyAtHHMM:
            guard hasActiveDays, let dailyTime else { return nil }
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = dailyTime.hour
            components.minute = dailyTime.minute
            components.second = 0

            guard let candidate = calendar.date(from: components) else {
                return nil
            }

            let start = candidate <= now
                ? (calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate)
                : candidate
            return nextAllowedDate(onOrAfter: start, calendar: calendar)
        }
    }

    private func nextAllowedDate(onOrAfter candidate: Date, calendar: Calendar) -> Date? {
        guard hasActiveDays else { return nil }
        if runsEveryDay || includes(candidate, calendar: calendar) {
            return candidate
        }

        let time = calendar.dateComponents([.hour, .minute, .second], from: candidate)
        for dayOffset in 1...7 {
            guard let shifted = calendar.date(byAdding: .day, value: dayOffset, to: candidate),
                  let weekday = TaskScheduleWeekday(calendarWeekday: calendar.component(.weekday, from: shifted)),
                  weekdays.contains(weekday) else {
                continue
            }

            var components = calendar.dateComponents([.year, .month, .day], from: shifted)
            components.hour = time.hour
            components.minute = time.minute
            components.second = time.second
            return calendar.date(from: components)
        }

        return nil
    }
}
