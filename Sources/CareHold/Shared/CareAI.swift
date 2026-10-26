import Core
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model, used only where it adds clarity and always grounded on the
/// patient's own plan. Nothing leaves the iPhone. Every iPhone gets the rule-based answers
/// from Core first; the model only:
///   1. answers patient questions the rules don't understand, using only the plan as facts;
///   2. rewrites a clinician's note in plain, short words ("Explain simply");
///   3. turns a clinician's sentence into a plan item draft when the rules can't.
/// It never diagnoses, never changes a dose and always points to the clinician or 911.
enum CareAI {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// Answer to a free question, or nil when the model is unavailable or fails.
    static func answer(_ question: String, facts: String, clinicianName: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), isAvailable {
            let session = LanguageModelSession(instructions: """
                You help an older adult understand their own care plan from their physical therapist \
                or doctor, \(clinicianName). Use ONLY the facts below. Answer in two or three short, \
                warm, plain sentences, like talking to a grandparent. No lists, no markdown.
                Rules:
                - Never diagnose, never suggest new medicines, never change a dose, time or exercise.
                - If the facts do not answer the question, say you are not sure and suggest asking \
                \(clinicianName) with the button below.
                - If anything sounds like an emergency (chest pain, trouble breathing, a fall, \
                bleeding, fainting), tell them to call 911 now.

                FACTS:
                \(facts)
                """)
            do {
                return try await session.respond(to: question).content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    /// The same note in simpler words, or nil when unavailable.
    static func simplify(_ text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), isAvailable {
            let session = LanguageModelSession(instructions: """
                Rewrite health instructions for an older adult in very plain words. Keep every fact, \
                number, time and warning exactly. Do not add advice. Use short sentences, at most five. \
                No markdown.
                """)
            do {
                return try await session.respond(to: text).content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    /// A plan item draft from a clinician's sentence: rules first, then the model.
    static func draft(from sentence: String) async -> PlanItemDraft? {
        let ruleBased = PlanItemParser.parse(sentence)
        // The rules are trusted when they found the schedule; otherwise the model may read it better.
        if let ruleBased, !ruleBased.times.isEmpty || ruleBased.kind == .instruction { return ruleBased }
        #if canImport(FoundationModels)
        if #available(iOS 26, *), isAvailable, let modelDraft = await modelDraft(from: sentence) {
            return modelDraft
        }
        #endif
        return ruleBased
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    @Generable
    struct Extraction {
        @Guide(description: "One of: medication, exercise, instruction")
        var kind: String
        @Guide(description: "Short name, e.g. Ibuprofen or Heel slides")
        var title: String
        @Guide(description: "Dose or amount, e.g. 400 mg, 1 tablet or 3 sets of 10. Empty if none.")
        var dosage: String
        @Guide(description: "Practical notes from the sentence, e.g. Take with food. Empty if none.")
        var instructions: String
        @Guide(description: "Times of day in 24-hour HH:MM, e.g. 08:00. Empty list for anytime.")
        var times: [String]
        @Guide(description: "ISO weekdays 1=Monday..7=Sunday. Empty list for every day.")
        var weekdays: [Int]
        @Guide(description: "How many days it lasts, 0 if ongoing")
        var durationDays: Int
    }

    @available(iOS 26, *)
    private static func modelDraft(from sentence: String) async -> PlanItemDraft? {
        let session = LanguageModelSession(instructions: """
            Extract one care plan item a physical therapist or doctor dictated. Never invent doses or times \
            that are not in the sentence; "twice a day" means 08:00 and 20:00, "three times a day" means \
            08:00, 14:00 and 20:00, "at bedtime" means 21:00.
            """)
        guard let result = try? await session.respond(to: sentence, generating: Extraction.self).content else {
            return nil
        }
        let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let dosage = result.dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = result.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlanItemDraft(
            kind: PlanItem.Kind(rawValue: result.kind) ?? .instruction,
            title: String(title.prefix(120)),
            dosage: dosage.isEmpty ? nil : String(dosage.prefix(120)),
            instructions: notes.isEmpty ? nil : String(notes.prefix(2000)),
            times: Array(Set(result.times.compactMap(LocalTime.init(string:)))).sorted(),
            weekdays: Set(result.weekdays.filter { (1...7).contains($0) }),
            durationDays: result.durationDays > 0 ? min(result.durationDays, 365) : nil
        )
    }
    #endif
}

/// The patient's plan as plain facts for the model. Only their own data, nothing else.
enum CareFacts {
    static func text(context: AssistantContext, summaries: [Appointment]) -> String {
        var lines: [String] = []
        lines.append("Now: \(Format.dayAndTime(context.now)).")
        if let next = context.nextAppointment {
            lines.append("Next visit: \(next.title), \(Format.dayAndTime(next.startsAt))\(next.location.map { " at \($0)" } ?? "").")
        } else {
            lines.append("No upcoming visit is scheduled.")
        }
        for item in context.activeItems {
            var line = "\(Format.kind(item.kind)): \(item.title)"
            if let dosage = item.dosage { line += " (\(dosage))" }
            line += ". \(Format.schedule(item))."
            if let notes = item.instructions { line += " Notes: \(notes)" }
            lines.append(line)
        }
        let pending = context.todayTasks.filter { !$0.isDone }
        if pending.isEmpty {
            lines.append("Everything for today is done.")
        } else {
            let list = pending.map { task in "\(task.item.title)\(task.slot.map { " at \(Format.time($0))" } ?? "")" }
            lines.append("Still to do today: \(list.joined(separator: "; ")).")
        }
        for visit in summaries.prefix(2) {
            if let summary = visit.visitSummary {
                lines.append("Notes from the visit on \(Format.shortDay(visit.startsAt)): \(summary)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
