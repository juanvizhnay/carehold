import Foundation

/// Client-generated identifiers. UUIDv7 (time-ordered) keeps database indexes compact and makes
/// retried writes idempotent: the same draft always carries the same id.
public enum EntityID {
    public static func make(now: Date = Date()) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        let millis = UInt64(max(0, now.timeIntervalSince1970 * 1000))
        for index in 0..<6 {
            bytes[index] = UInt8(truncatingIfNeeded: millis >> (8 * (5 - index)))
        }
        var generator = SystemRandomNumberGenerator()
        for index in 6..<16 {
            bytes[index] = UInt8.random(in: .min ... .max, using: &generator)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70 // version 7
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// A calendar day without time or time zone ("2026-10-16"). Plan dates are days, and
/// storing them as `Date` causes off-by-one bugs when the user travels or the zone changes.
public struct CalendarDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...CalendarDate.daysInMonth(year: year, month: month)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses "YYYY-MM-DD".
    public init?(isoString: String) {
        let parts = isoString.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// Today in the given calendar/time zone (the user's current one by default).
    public static func today(calendar: Calendar = .current, now: Date = Date()) -> CalendarDate {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return CalendarDate(year: parts.year!, month: parts.month!, day: parts.day!)!
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { isoString }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        case 2: isLeapYear(year) ? 29 : 28
        default: 0
        }
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = CalendarDate(isoString: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(raw)")
        }
        self = date
    }
}
