import Foundation

/// A plan item the clinician described in one sentence, before they review and save it.
public struct PlanItemDraft: Equatable, Sendable {
    public var kind: PlanItem.Kind
    public var title: String
    public var dosage: String?
    public var instructions: String?
    public var times: [LocalTime]
    public var weekdays: Set<Int>
    /// Length of the course in days ("for 5 days"); nil when ongoing.
    public var durationDays: Int?

    public init(
        kind: PlanItem.Kind, title: String, dosage: String? = nil, instructions: String? = nil,
        times: [LocalTime] = [], weekdays: Set<Int> = [], durationDays: Int? = nil
    ) {
        self.kind = kind
        self.title = title
        self.dosage = dosage
        self.instructions = instructions
        self.times = times
        self.weekdays = weekdays
        self.durationDays = durationDays
    }
}

/// Rule-based reading of sentences like "Ibuprofen 400 mg twice a day for 5 days" or
/// "Heel slides, 3 sets of 10, every morning". Runs on every iPhone; the on-device model
/// only takes over when these rules cannot find a title.
public enum PlanItemParser {
    public static func parse(_ text: String) -> PlanItemDraft? {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return nil }
        let lower = sentence.lowercased()

        let dosage = firstMatch(dosagePattern, in: sentence)
        let sets = firstMatch(setsPattern, in: sentence)
        let duration = durationDays(in: lower)
        let times = times(in: lower)
        let weekdays = weekdays(in: lower)
        let kind = kind(of: lower, hasDosage: dosage != nil, hasSets: sets != nil)

        // The title is what is left before the first detail ("Ibuprofen", "Heel slides").
        var title = sentence
        for marker in [dosage, sets].compactMap({ $0 }) + scheduleWords where !marker.isEmpty {
            if let range = title.range(of: marker, options: .caseInsensitive), range.lowerBound > title.startIndex {
                title = String(title[..<range.lowerBound])
            }
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ,.-:;").union(.whitespacesAndNewlines))
        guard !title.isEmpty else { return nil }
        title = title.prefix(1).uppercased() + title.dropFirst()

        return PlanItemDraft(
            kind: kind,
            title: String(title.prefix(120)),
            dosage: (dosage ?? sets).map { String($0.prefix(120)) },
            instructions: instructions(in: lower),
            times: times,
            weekdays: weekdays,
            durationDays: duration
        )
    }

    // MARK: - Pieces

    private static let dosagePattern = #"\d+(?:[.,]\d+)?\s?(?:mg|mcg|µg|ml|g|iu|units?|tablets?|tabs?|pills?|capsules?|caps?|drops?|puffs?|sprays?)\b"#
    private static let setsPattern = #"\d+\s?(?:sets?|x)\s?(?:of\s)?\d+(?:\s?(?:reps?|repetitions|times))?|\d+\s?(?:reps?|repetitions|minutes|mins?)\b"#

    /// Words that start the schedule part of a sentence; the title ends before them.
    private static let scheduleWords = [
        " once", " twice", " three times", " 3 times", " every", " daily", " each", " at night",
        " at bedtime", " before", " after", " with ", " for ", " in the morning", " on ",
    ]

    private static func kind(of lower: String, hasDosage: Bool, hasSets: Bool) -> PlanItem.Kind {
        let exerciseWords = ["exercise", "stretch", "walk", "slide", "raise", "squat", "bridge", "sets", "reps",
                             "bike", "march", "balance", "lift", "curl", "press", "rotation", "ice", "heat"]
        if hasSets || exerciseWords.contains(where: { lower.contains($0) }) && !hasDosage {
            return .exercise
        }
        let medicationWords = ["tablet", "pill", "capsule", "mg", "dose", "take ", "cream", "ointment", "drops", "inhaler"]
        if hasDosage || medicationWords.contains(where: { lower.contains($0) }) {
            return .medication
        }
        return .instruction
    }

    static func times(in lower: String) -> [LocalTime] {
        var result: [LocalTime] = []
        func add(_ hour: Int, _ minute: Int = 0) {
            if let time = LocalTime(hour: hour, minute: minute), !result.contains(time) { result.append(time) }
        }

        // Explicit clock times: "at 8", "8:30 am", "9pm".
        if let regex = try? NSRegularExpression(pattern: #"(?:at\s)?(\d{1,2})(?::(\d{2}))?\s?(am|pm)\b|at\s(\d{1,2})(?::(\d{2}))?\b"#) {
            let range = NSRange(lower.startIndex..., in: lower)
            for match in regex.matches(in: lower, range: range) {
                let hourGroup = match.range(at: 1).location != NSNotFound ? 1 : 4
                let minuteGroup = hourGroup == 1 ? 2 : 5
                guard let hourRange = Range(match.range(at: hourGroup), in: lower),
                      var hour = Int(lower[hourRange]) else { continue }
                let minute = Range(match.range(at: minuteGroup), in: lower).flatMap { Int(lower[$0]) } ?? 0
                if let meridiemRange = Range(match.range(at: 3), in: lower) {
                    let meridiem = lower[meridiemRange]
                    if meridiem == "pm", hour < 12 { hour += 12 }
                    if meridiem == "am", hour == 12 { hour = 0 }
                }
                add(hour, minute)
            }
        }
        if !result.isEmpty { return result.sorted() }

        if lower.contains("four times") || lower.contains("4 times") || lower.contains("every 6 hours") {
            [8, 12, 16, 20].forEach { add($0) }
        } else if lower.contains("three times") || lower.contains("3 times") || lower.contains("every 8 hours") {
            [8, 14, 20].forEach { add($0) }
        } else if lower.contains("twice") || lower.contains("2 times") || lower.contains("every 12 hours") {
            [8, 20].forEach { add($0) }
        } else {
            if lower.contains("morning") || lower.contains("breakfast") { add(8) }
            if lower.contains("lunch") || lower.contains("noon") || lower.contains("afternoon") { add(13) }
            if lower.contains("dinner") || lower.contains("evening") { add(19) }
            if lower.contains("night") || lower.contains("bedtime") || lower.contains("before bed") { add(21) }
            if result.isEmpty, lower.contains("once a day") || lower.contains("daily") || lower.contains("every day") {
                add(9)
            }
        }
        return result.sorted()
    }

    static func weekdays(in lower: String) -> Set<Int> {
        let names: [(String, Int)] = [
            ("monday", 1), ("tuesday", 2), ("wednesday", 3), ("thursday", 4), ("friday", 5), ("saturday", 6), ("sunday", 7),
        ]
        var days = Set(names.filter { lower.contains($0.0) }.map(\.1))
        if days.isEmpty {
            if lower.contains("weekdays") { days = [1, 2, 3, 4, 5] }
            if lower.contains("three times a week") || lower.contains("3 times a week") { days = [1, 3, 5] }
            if lower.contains("twice a week") || lower.contains("2 times a week") { days = [2, 4] }
        }
        return days
    }

    static func durationDays(in lower: String) -> Int? {
        guard let match = firstMatch(#"for\s(\d{1,3}|one|two|three|four|five|six|seven|ten|fourteen)\s(days?|weeks?)"#, in: lower) else {
            return nil
        }
        let parts = match.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "ten": 10, "fourteen": 14]
        guard let count = Int(parts[1]) ?? words[String(parts[1])], count > 0 else { return nil }
        return parts[2].hasPrefix("week") ? count * 7 : count
    }

    /// Short practical notes worth keeping ("with food").
    private static func instructions(in lower: String) -> String? {
        let notes = [
            ("with food", "Take with food."), ("with meals", "Take with meals."), ("empty stomach", "Take on an empty stomach."),
            ("with water", "Take with a full glass of water."), ("as needed", "Only when needed."), ("if needed", "Only when needed."),
        ]
        let found = notes.filter { lower.contains($0.0) }.map(\.1)
        return found.isEmpty ? nil : Array(Set(found)).sorted().joined(separator: " ")
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return String(text[range])
    }
}
