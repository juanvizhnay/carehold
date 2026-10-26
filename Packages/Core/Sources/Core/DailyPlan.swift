import Foundation

/// One thing the patient should do on a given day: a dose, an exercise session or an instruction.
public struct PlanTask: Identifiable, Hashable, Sendable {
    public let item: PlanItem
    public let day: CalendarDate
    /// Nil for "anytime today".
    public let slot: LocalTime?
    /// The log that marks it done, if any.
    public let log: PlanLog?

    public var id: String { "\(item.id.uuidString)|\(day.isoString)|\(slot?.string ?? "any")" }
    public var isDone: Bool { log != nil }
}

/// Times of day the way people talk about them, so the list reads like a pill organizer.
public enum DayPart: Int, CaseIterable, Comparable, Sendable {
    case morning
    case afternoon
    case evening
    case anytime

    public init(slot: LocalTime?) {
        guard let slot else {
            self = .anytime
            return
        }
        switch slot.hour {
        case ..<12: self = .morning
        case 12..<17: self = .afternoon
        default: self = .evening
        }
    }

    public static func < (lhs: DayPart, rhs: DayPart) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum DailyPlan {
    /// Everything due on `day`, in time order, with "anytime" items last.
    public static func tasks(for day: CalendarDate, items: [PlanItem], logs: [PlanLog]) -> [PlanTask] {
        let logsByKey = Dictionary(
            logs.filter { $0.dueOn == day }.map { (key($0.itemID, $0.slot), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var tasks: [PlanTask] = []
        for item in items where item.isDue(on: day) {
            let slots: [LocalTime?] = item.times.isEmpty ? [nil] : item.times
            for slot in slots {
                tasks.append(PlanTask(item: item, day: day, slot: slot, log: logsByKey[key(item.id, slot)]))
            }
        }
        return tasks.sorted { lhs, rhs in
            switch (lhs.slot, rhs.slot) {
            case let (l?, r?) where l != r: return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.item.title.localizedStandardCompare(rhs.item.title) == .orderedAscending
            }
        }
    }

    public static func grouped(_ tasks: [PlanTask]) -> [(part: DayPart, tasks: [PlanTask])] {
        let groups = Dictionary(grouping: tasks) { DayPart(slot: $0.slot) }
        return DayPart.allCases.compactMap { part in
            guard let tasks = groups[part], !tasks.isEmpty else { return nil }
            return (part, tasks)
        }
    }

    /// The first unfinished task at or after `time`, else the first unfinished one overall.
    public static func next(in tasks: [PlanTask], after time: LocalTime) -> PlanTask? {
        let pending = tasks.filter { !$0.isDone }
        return pending.first { ($0.slot ?? time) >= time } ?? pending.first
    }

    /// Share of scheduled tasks marked done across `days` (nil when nothing was scheduled).
    public static func adherence(items: [PlanItem], logs: [PlanLog], days: [CalendarDate]) -> Double? {
        var due = 0
        var done = 0
        for day in days {
            let tasks = Self.tasks(for: day, items: items, logs: logs)
            due += tasks.count
            done += tasks.filter(\.isDone).count
        }
        return due == 0 ? nil : Double(done) / Double(due)
    }

    private static func key(_ itemID: UUID, _ slot: LocalTime?) -> String {
        "\(itemID.uuidString)|\(slot?.string ?? "any")"
    }
}
