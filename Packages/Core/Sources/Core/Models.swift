import Foundation

public enum Role: String, Codable, Sendable {
    case patient
    case clinician
}

public struct Profile: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var role: Role
    public var fullName: String
    public var clinicName: String?
    /// Clinicians only: the code a patient types once to join them.
    public var clinicianCode: String?
    public var phone: String?

    public init(id: UUID, role: Role, fullName: String, clinicName: String? = nil, clinicianCode: String? = nil, phone: String? = nil) {
        self.id = id
        self.role = role
        self.fullName = fullName
        self.clinicName = clinicName
        self.clinicianCode = clinicianCode
        self.phone = phone
    }

    /// "Robert" from "Robert Johnson"; the whole name when there is no space.
    public var firstName: String {
        let trimmed = fullName.trimmingCharacters(in: .whitespaces)
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    /// Patients see their clinician by name, falling back to the practice name.
    public var displayName: String {
        let trimmed = fullName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return clinicName ?? ""
    }
}

/// A clock time without a date or time zone ("08:00"), for daily schedules.
public struct LocalTime: Hashable, Comparable, Codable, Sendable {
    public let hour: Int
    public let minute: Int

    public init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Parses "08:00" or Postgres' "08:00:00".
    public init?(string: String) {
        let parts = string.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var string: String { String(format: "%02d:%02d", hour, minute) }
    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let time = LocalTime(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid time \(raw)")
        }
        self = time
    }
}

public struct Appointment: Identifiable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// The patient asked for a visit; the clinician has not confirmed a time.
        case requested
        case scheduled
        case completed
        case cancelled
    }

    public let id: UUID
    public let clinicianID: UUID
    public let patientID: UUID
    public var startsAt: Date
    public var durationMinutes: Int
    public var title: String
    public var location: String?
    public var status: Status
    /// What the clinician wrote after the visit.
    public var visitSummary: String?
    /// What the patient wrote when asking for the visit.
    public var patientNote: String?

    public init(
        id: UUID = EntityID.make(), clinicianID: UUID, patientID: UUID, startsAt: Date,
        durationMinutes: Int = 45, title: String, location: String? = nil, status: Status = .scheduled,
        visitSummary: String? = nil, patientNote: String? = nil
    ) {
        self.id = id
        self.clinicianID = clinicianID
        self.patientID = patientID
        self.startsAt = startsAt
        self.durationMinutes = durationMinutes
        self.title = title
        self.location = location
        self.status = status
        self.visitSummary = visitSummary
        self.patientNote = patientNote
    }

    public var endsAt: Date { startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60)) }

    /// Past visits: finished ones, plus scheduled ones whose end has gone by.
    public func isPast(now: Date) -> Bool {
        switch status {
        case .completed: true
        case .cancelled: startsAt < now
        case .scheduled: endsAt < now
        case .requested: false
        }
    }
}

public struct PlanItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case medication
        case exercise
        case instruction
    }

    public let id: UUID
    public let clinicianID: UUID
    public let patientID: UUID
    public var kind: Kind
    public var title: String
    public var dosage: String?
    public var instructions: String?
    /// Empty: anytime during the day.
    public var times: [LocalTime]
    /// ISO weekdays (1 Monday ... 7 Sunday). Empty: every day.
    public var weekdays: Set<Int>
    public var startDate: CalendarDate
    public var endDate: CalendarDate?
    /// The visit where it was prescribed.
    public var appointmentID: UUID?
    public var archivedAt: Date?

    public init(
        id: UUID = EntityID.make(), clinicianID: UUID, patientID: UUID, kind: Kind, title: String,
        dosage: String? = nil, instructions: String? = nil, times: [LocalTime] = [], weekdays: Set<Int> = [],
        startDate: CalendarDate, endDate: CalendarDate? = nil, appointmentID: UUID? = nil, archivedAt: Date? = nil
    ) {
        self.id = id
        self.clinicianID = clinicianID
        self.patientID = patientID
        self.kind = kind
        self.title = title
        self.dosage = dosage
        self.instructions = instructions
        self.times = times.sorted()
        self.weekdays = weekdays
        self.startDate = startDate
        self.endDate = endDate
        self.appointmentID = appointmentID
        self.archivedAt = archivedAt
    }

    public func isActive(on day: CalendarDate) -> Bool {
        guard archivedAt == nil, startDate <= day else { return false }
        if let endDate, day > endDate { return false }
        return true
    }

    public func isDue(on day: CalendarDate) -> Bool {
        isActive(on: day) && (weekdays.isEmpty || weekdays.contains(day.isoWeekday))
    }
}

public struct PlanLog: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let itemID: UUID
    public let patientID: UUID
    public let dueOn: CalendarDate
    public let slot: LocalTime?
    public let doneAt: Date

    public init(id: UUID = EntityID.make(), itemID: UUID, patientID: UUID, dueOn: CalendarDate, slot: LocalTime?, doneAt: Date = Date()) {
        self.id = id
        self.itemID = itemID
        self.patientID = patientID
        self.dueOn = dueOn
        self.slot = slot
        self.doneAt = doneAt
    }
}

public struct Message: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case message
        /// Sent by the clinician; shown on the patient's Today screen until acknowledged.
        case reminder
    }

    public let id: UUID
    public let clinicianID: UUID
    public let patientID: UUID
    public let senderID: UUID
    public var kind: Kind
    public var body: String
    public var createdAt: Date
    public var readAt: Date?

    public init(
        id: UUID = EntityID.make(), clinicianID: UUID, patientID: UUID, senderID: UUID, kind: Kind = .message,
        body: String, createdAt: Date = Date(), readAt: Date? = nil
    ) {
        self.id = id
        self.clinicianID = clinicianID
        self.patientID = patientID
        self.senderID = senderID
        self.kind = kind
        self.body = body
        self.createdAt = createdAt
        self.readAt = readAt
    }
}
