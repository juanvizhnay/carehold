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

        // Emergencies match exactly: a "close" word could turn "paint" into "faint".
        if emergencyWords.contains(where: lower.contains) { return .emergency }

        let words = words(in: lower)
        func mentions(_ keywords: [String]) -> Bool {
            keywords.contains { keyword in
                lower.contains(keyword) || (isFuzzyKeyword(keyword) && words.contains { isClose($0, to: keyword) })
            }
        }

        let item = mentionedItem(in: lower, items: context.activeItems)
        if mentions(["forgot", "missed", "skipped", "didn't take", "did not take", "double dose", "took two"]) {
            return .missedDose(item)
        }
        if let item { return .item(item) }

        if mentions(["appointment", "visit", "session", "therapy", "checkup", "check-up", "consultation", "see the doctor", "see my", "come in", "next time"]) {
            return .nextAppointment(context.nextAppointment)
        }

        let remaining = context.todayTasks.filter { !$0.isDone }
        if mentions([" pill", "medicine", "medication", "meds", "tablet", "take "]) {
            return .today(remaining.filter { $0.item.kind == .medication }, kind: .medication)
        }
        if mentions(["exercise", "stretch", "workout", "routine"]) {
            return .today(remaining.filter { $0.item.kind == .exercise }, kind: .exercise)
        }
        if mentions(["today", "what do i", "what should i", "to do", "left", "plan"]) {
            return .today(remaining, kind: nil)
        }
        return .unknown
    }

    static let emergencyWords = [
        "chest pain", "can't breathe", "cant breathe", "cannot breathe", "short of breath", "trouble breathing",
        "i fell", "fell down", "i've fallen", "bleeding", "emergency", "911", "stroke", "heart attack",
        "faint", "passed out", "unconscious", "numbness", " numb ", "slurred", "overdose", "took too many",
    ]

    /// An item whose title (or a long word of it, even misspelled) appears in the question.
    static func mentionedItem(in lower: String, items: [PlanItem]) -> PlanItem? {
        let questionWords = words(in: lower)
        let candidates = items.compactMap { item -> (PlanItem, Int)? in
            let title = item.title.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            if lower.contains(title) { return (item, title.count + 100) }
            let titleWords = words(in: title).filter { $0.count >= 5 && !genericWords.contains($0) }
            let hits = titleWords.filter { word in lower.contains(word) || questionWords.contains { isClose($0, to: word) } }
            return hits.isEmpty ? nil : (item, hits.map(\.count).reduce(0, +))
        }
        return candidates.max { $0.1 < $1.1 }?.0
    }

    private static func words(in text: String) -> [String] {
        text.split { !$0.isLetter }.map(String.init)
    }

    /// Single long words are matched with typos too; phrases and short words only exactly.
    private static func isFuzzyKeyword(_ keyword: String) -> Bool {
        keyword.count >= 6 && keyword.allSatisfy(\.isLetter)
    }

    /// A typo away from `target`: one edit for words of 5 to 7 letters, two from 8.
    /// The first letter must match, which keeps unrelated words apart.
    static func isClose(_ word: String, to target: String) -> Bool {
        guard target.count >= 5, word.first == target.first else { return false }
        let allowed = target.count >= 8 ? 2 : 1
        guard abs(word.count - target.count) <= allowed else { return false }
        return editDistance(Array(word), Array(target)) <= allowed
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1]
            for (j, y) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Words too common in titles to identify one item ("exercise", "daily").
    private static let genericWords: Set<String> = ["exercise", "exercises", "daily", "stretch", "morning", "evening", "tablet", "tablets"]
}
