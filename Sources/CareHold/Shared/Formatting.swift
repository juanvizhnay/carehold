import Core
import Foundation

/// Dates and times the way people say them, always in the user's locale and time zone.
enum Format {
    static func time(_ value: LocalTime) -> String {
        var components = DateComponents()
        components.hour = value.hour
        components.minute = value.minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Today", "Tomorrow", "Yesterday" or "Thursday, October 28".
    static func day(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear
            ? date.formatted(.dateTime.weekday(.wide).month(.wide).day())
            : date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// "Thursday, October 28 at 10:30 AM".
    static func dayAndTime(_ date: Date) -> String {
        "\(day(date)) at \(time(date))"
    }

    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func longToday(_ date: Date = Date()) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    static func greeting(_ date: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    static func dayPart(_ part: DayPart) -> String {
        switch part {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .anytime: "Anytime today"
        }
    }

    static func kind(_ kind: PlanItem.Kind) -> String {
        switch kind {
        case .medication: "Medicine"
        case .exercise: "Exercise"
        case .instruction: "Instruction"
        }
    }

    static func kindPlural(_ kind: PlanItem.Kind) -> String {
        switch kind {
        case .medication: "Medicines"
        case .exercise: "Exercises"
        case .instruction: "Instructions"
        }
    }

    /// "Every day at 8:00 AM and 8:00 PM", "Mon, Wed, Fri at 10:00 AM", "Every day, anytime".
    static func schedule(_ item: PlanItem) -> String {
        let days: String
        if item.weekdays.isEmpty || item.weekdays.count == 7 {
            days = "Every day"
        } else {
            let symbols = Calendar.current.shortWeekdaySymbols // Sunday first
            days = item.weekdays.sorted().map { symbols[$0 % 7] }.joined(separator: ", ")
        }
        guard !item.times.isEmpty else { return "\(days), anytime" }
        return "\(days) at \(item.times.map(time).formatted(.list(type: .and)))"
    }

    static func calendarDate(_ day: CalendarDate) -> Date {
        Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) ?? Date()
    }

    static func calendarDate(from date: Date) -> CalendarDate {
        CalendarDate.today(calendar: .current, now: date)
    }

    static func localTime(from date: Date) -> LocalTime {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return LocalTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0) ?? LocalTime(hour: 0, minute: 0)!
    }

    static func errorText(_ error: CareError) -> String {
        switch error {
        case .network: "You seem to be offline. Please try again."
        case .notAllowed: "That isn't allowed. Please sign in again."
        case .codeNotFound: "We couldn't find that code. Please check it and try again."
        case .unknown: "Something went wrong. Please try again."
        }
    }
}
