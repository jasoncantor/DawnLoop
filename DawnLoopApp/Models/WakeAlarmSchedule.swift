import SwiftData
import Foundation

/// Days of the week for repeat scheduling
struct WeekdaySchedule: Codable, Sendable, Equatable {
    var sunday: Bool
    var monday: Bool
    var tuesday: Bool
    var wednesday: Bool
    var thursday: Bool
    var friday: Bool
    var saturday: Bool

    static let everyDay = WeekdaySchedule(
        sunday: true, monday: true, tuesday: true, wednesday: true,
        thursday: true, friday: true, saturday: true
    )

    static let weekdays = WeekdaySchedule(
        sunday: false, monday: true, tuesday: true, wednesday: true,
        thursday: true, friday: true, saturday: false
    )

    static let weekends = WeekdaySchedule(
        sunday: true, monday: false, tuesday: false, wednesday: false,
        thursday: false, friday: false, saturday: true
    )

    static let never = WeekdaySchedule(
        sunday: false, monday: false, tuesday: false, wednesday: false,
        thursday: false, friday: false, saturday: false
    )

    init(
        sunday: Bool = false,
        monday: Bool = false,
        tuesday: Bool = false,
        wednesday: Bool = false,
        thursday: Bool = false,
        friday: Bool = false,
        saturday: Bool = false
    ) {
        self.sunday = sunday
        self.monday = monday
        self.tuesday = tuesday
        self.wednesday = wednesday
        self.thursday = thursday
        self.friday = friday
        self.saturday = saturday
    }

    var isRepeating: Bool {
        sunday || monday || tuesday || wednesday || thursday || friday || saturday
    }

    var activeDaysCount: Int {
        var count = 0
        if sunday { count += 1 }
        if monday { count += 1 }
        if tuesday { count += 1 }
        if wednesday { count += 1 }
        if thursday { count += 1 }
        if friday { count += 1 }
        if saturday { count += 1 }
        return count
    }

    var displayText: String {
        if self == .everyDay {
            return "Every day"
        } else if self == .weekdays {
            return "Weekdays"
        } else if self == .weekends {
            return "Weekends"
        } else if !isRepeating {
            return "Once"
        } else if activeDaysCount == 1 {
            let dayName: String
            if sunday { dayName = "Sunday" }
            else if monday { dayName = "Monday" }
            else if tuesday { dayName = "Tuesday" }
            else if wednesday { dayName = "Wednesday" }
            else if thursday { dayName = "Thursday" }
            else if friday { dayName = "Friday" }
            else { dayName = "Saturday" }
            return dayName
        } else {
            var days: [String] = []
            if sunday { days.append("Sun") }
            if monday { days.append("Mon") }
            if tuesday { days.append("Tue") }
            if wednesday { days.append("Wed") }
            if thursday { days.append("Thu") }
            if friday { days.append("Fri") }
            if saturday { days.append("Sat") }
            return days.joined(separator: ", ")
        }
    }

    /// Check if the alarm should fire on a given date
    func shouldFire(on date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)

        switch weekday {
        case 1: return sunday
        case 2: return monday
        case 3: return tuesday
        case 4: return wednesday
        case 5: return thursday
        case 6: return friday
        case 7: return saturday
        default: return false
        }
    }
}

/// Persistent model for alarm schedule
/// Stored as a separate model for flexible querying and round-tripping (VAL-ALARM contract)
@Model
final class WakeAlarmSchedule: @unchecked Sendable {
    /// Unique identifier for this schedule record
    @Attribute(.unique) var id: UUID

    /// Reference to the alarm this schedule belongs to
    @Attribute(.unique) var alarmId: UUID

    /// Weekday repeat configuration
    var weekdaySchedule: WeekdaySchedule

    /// When this schedule was created
    var createdAt: Date

    /// When this schedule was last updated
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        alarmId: UUID,
        weekdaySchedule: WeekdaySchedule = .weekdays
    ) {
        self.id = id
        self.alarmId = alarmId
        self.weekdaySchedule = weekdaySchedule
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func update(weekdaySchedule: WeekdaySchedule) {
        self.weekdaySchedule = weekdaySchedule
        self.updatedAt = Date()
    }

    /// Get the repeat schedule for display
    var repeatSchedule: WeekdaySchedule {
        weekdaySchedule
    }

    /// Calculate the next occurrence after a given date
    func nextOccurrence(after date: Date = Date(), wakeTimeSeconds: Int) -> Date? {
        guard weekdaySchedule.isRepeating else {
            // For one-time alarms, return the wake time for today or tomorrow
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            let hours = wakeTimeSeconds / 3600
            let minutes = (wakeTimeSeconds % 3600) / 60
            components.hour = hours
            components.minute = minutes
            components.second = 0

            guard let wakeDate = calendar.date(from: components) else { return nil }

            // If wake time has passed, return tomorrow
            if wakeDate <= date {
                return calendar.date(byAdding: .day, value: 1, to: wakeDate)
            }
            return wakeDate
        }

        let calendar = Calendar.current

        // Check each day for the next 14 days
        for dayOffset in 0..<14 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }

            if weekdaySchedule.shouldFire(on: checkDate) {
                var components = calendar.dateComponents([.year, .month, .day], from: checkDate)
                let hours = wakeTimeSeconds / 3600
                let minutes = (wakeTimeSeconds % 3600) / 60
                components.hour = hours
                components.minute = minutes
                components.second = 0

                guard let wakeDate = calendar.date(from: components) else { continue }

                // For today, ensure wake time hasn't passed
                if dayOffset == 0 && wakeDate <= date {
                    continue
                }

                return wakeDate
            }
        }

        return nil
    }
}
