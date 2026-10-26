import Foundation

public extension CalendarDate {
    /// Integer Gregorian days-from-civil algorithm; independent of locale and time zone.
    /// Arithmetic requires a result in CalendarDate's supported years 1...9999.
    func adding(days: Int) -> CalendarDate {
        let (ordinal, overflow) = civilOrdinal.addingReportingOverflow(days)
        precondition(!overflow && ordinal >= 306 && ordinal <= 3_652_364, "Date outside years 1...9999")
        let era = ordinal / 146097
        let doe = ordinal - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        var year = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp + (mp < 10 ? 3 : -9)
        year += month <= 2 ? 1 : 0
        return CalendarDate(year: year, month: month, day: day)!
    }

    /// Retain the original anchor across short months (31 -> 28 -> 31).
    func adding(months: Int, clampingTo anchorDay: Int) -> CalendarDate {
        precondition((1...31).contains(anchorDay))
        let (index, overflow) = ((year - 1) * 12 + month - 1).addingReportingOverflow(months)
        precondition(!overflow && (0..<119988).contains(index), "Date outside years 1...9999")
        let year = index / 12 + 1
        let month = index % 12 + 1
        return CalendarDate(year: year, month: month, day: min(anchorDay, Self.daysInMonth(year: year, month: month)))!
    }

    func daysUntil(_ other: CalendarDate) -> Int { other.civilOrdinal - civilOrdinal }
    var startOfMonth: CalendarDate { CalendarDate(year: year, month: month, day: 1)! }
    var endOfMonth: CalendarDate {
        CalendarDate(year: year, month: month, day: Self.daysInMonth(year: year, month: month))!
    }

    /// ISO weekday: 1 is Monday, 7 is Sunday.
    var isoWeekday: Int {
        let daysSince1970 = civilOrdinal - 719_468
        return ((daysSince1970 % 7 + 7 + 3) % 7) + 1
    }

    private var civilOrdinal: Int {
        let y = year - (month <= 2 ? 1 : 0)
        let era = y / 400
        let yoe = y - era * 400
        let mp = month + (month > 2 ? -3 : 9)
        let doy = (153 * mp + 2) / 5 + day - 1
        return era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy
    }
}
