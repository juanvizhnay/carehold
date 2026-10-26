import Foundation

/// What a patient's question is about, answered only from their own care plan.
/// The rules never give medical advice: anything they cannot answer from the plan
/// goes to the clinician (or to the on-device model, which is told the same limits).
public enum AssistantAnswer: Equatable, Sendable {
    /// Words that may mean an emergency. Always wins: the screen shows "call 911".
    case emergency
    case nextAppointment(Appointment?)
    /// Remaining tasks today, optionally only medications or only exercises.
    case today([PlanTask], kind: PlanItem.Kind?)
    /// The question names one item of the plan ("how do I take the ibuprofen?").
    case item(PlanItem)
    /// "I forgot my pill": never guess, ask the clinician.
    case missedDose(PlanItem?)
    case unknown
}

public struct AssistantContext: Sendable {
    public let items: [PlanItem]
    public let todayTasks: [PlanTask]
    public let appointments: [Appointment]
    public let now: Date

    public init(items: [PlanItem], todayTasks: [PlanTask], appointments: [Appointment], now: Date) {
        self.items = items
        self.todayTasks = todayTasks
        self.appointments = appointments
        self.now = now
    }

    public var nextAppointment: Appointment? {
        appointments
            .filter { $0.status == .scheduled && $0.endsAt >= now }
            .min { $0.startsAt < $1.startsAt }
    }

    public var activeItems: [PlanItem] {
        let today = todayTasks.first?.day
        return items.filter { item in today.map(item.isActive(on:)) ?? (item.archivedAt == nil) }
    }
}

public enum CareAssistant {
    public static func answer(_ question: String, context: AssistantContext) -> AssistantAnswer {
        let lower = " " + question.lowercased().folding(options: .diacriticInsensitive, locale: nil) + " "

        if emergencyWords.contains(where: lower.contains) { return .emergency }

        let item = mentionedItem(in: lower, items: context.activeItems)
        if ["forgot", "missed", "skipped", "didn't take", "did not take", "double dose", "took two"].contains(where: lower.contains) {
            return .missedDose(item)
        }
        if let item { return .item(item) }

        if ["appointment", "visit", "session", "therapy", "checkup", "check-up", "consultation", "see the doctor", "see my", "come in", "next time"].contains(where: lower.contains) {
            return .nextAppointment(context.nextAppointment)
        }

        let remaining = context.todayTasks.filter { !$0.isDone }
        if [" pill", "medicine", "medication", "meds", "tablet", "take "].contains(where: lower.contains) {
            return .today(remaining.filter { $0.item.kind == .medication }, kind: .medication)
        }
        if ["exercise", "stretch", "workout", "routine"].contains(where: lower.contains) {
            return .today(remaining.filter { $0.item.kind == .exercise }, kind: .exercise)
        }
        if ["today", "what do i", "what should i", "to do", "left", "plan"].contains(where: lower.contains) {
            return .today(remaining, kind: nil)
        }
        return .unknown
    }

    static let emergencyWords = [
        "chest pain", "can't breathe", "cant breathe", "cannot breathe", "short of breath", "trouble breathing",
        "i fell", "fell down", "i've fallen", "bleeding", "emergency", "911", "stroke", "heart attack",
        "faint", "passed out", "unconscious", "numbness", " numb ", "slurred", "overdose", "took too many",
    ]

    /// An item whose title (or a long word of it) appears in the question.
    static func mentionedItem(in lower: String, items: [PlanItem]) -> PlanItem? {
        let candidates = items.compactMap { item -> (PlanItem, Int)? in
            let title = item.title.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            if lower.contains(title) { return (item, title.count + 100) }
            let words = title.split { !$0.isLetter }.map(String.init).filter { $0.count >= 5 && !genericWords.contains($0) }
            let hits = words.filter { lower.contains($0) }
            return hits.isEmpty ? nil : (item, hits.map(\.count).reduce(0, +))
        }
        return candidates.max { $0.1 < $1.1 }?.0
    }

    /// Words too common in titles to identify one item ("exercise", "daily").
    private static let genericWords: Set<String> = ["exercise", "exercises", "daily", "stretch", "morning", "evening", "tablet", "tablets"]
}
