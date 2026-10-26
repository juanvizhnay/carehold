import Foundation
import Testing
@testable import Core

private let clinician = UUID()
private let patient = UUID()
private let monday = CalendarDate(year: 2026, month: 10, day: 26)!

private func time(_ text: String) -> LocalTime { LocalTime(string: text)! }

private func item(_ title: String, kind: PlanItem.Kind = .medication, times: [String] = [], weekdays: Set<Int> = [], end: CalendarDate? = nil) -> PlanItem {
    PlanItem(clinicianID: clinician, patientID: patient, kind: kind, title: title, times: times.map(time), weekdays: weekdays, startDate: monday.adding(days: -7), endDate: end)
}

@Suite struct CalendarTests {
    @Test func isoWeekday() {
        #expect(monday.isoWeekday == 1)
        #expect(monday.adding(days: 6).isoWeekday == 7)
        #expect(CalendarDate(year: 1970, month: 1, day: 1)!.isoWeekday == 4)
    }

    @Test func localTimeParsesPostgres() {
        #expect(LocalTime(string: "08:30:00") == LocalTime(hour: 8, minute: 30))
        #expect(LocalTime(string: "25:00") == nil)
    }
}

@Suite struct DailyPlanTests {
    @Test func expandsTimesAndSortsAnytimeLast() {
        let pills = item("Ibuprofen", times: ["20:00", "08:00"])
        let walk = item("Walk", kind: .exercise)
        let tasks = DailyPlan.tasks(for: monday, items: [walk, pills], logs: [])
        #expect(tasks.map(\.slot) == [time("08:00"), time("20:00"), nil])
        #expect(DailyPlan.grouped(tasks).map(\.part) == [.morning, .evening, .anytime])
    }

    @Test func respectsWeekdaysAndEndDate() {
        let weekly = item("Bike", kind: .exercise, weekdays: [2, 4])
        let ended = item("Antibiotic", end: monday.adding(days: -1))
        #expect(DailyPlan.tasks(for: monday, items: [weekly, ended], logs: []).isEmpty)
        #expect(DailyPlan.tasks(for: monday.adding(days: 1), items: [weekly], logs: []).count == 1)
    }

    @Test func logsMarkTheMatchingSlotDone() {
        let pills = item("Ibuprofen", times: ["08:00", "20:00"])
        let log = PlanLog(itemID: pills.id, patientID: patient, dueOn: monday, slot: time("08:00"))
        let tasks = DailyPlan.tasks(for: monday, items: [pills], logs: [log])
        #expect(tasks.map(\.isDone) == [true, false])
        #expect(DailyPlan.next(in: tasks, after: time("07:00"))?.slot == time("20:00"))
        #expect(DailyPlan.adherence(items: [pills], logs: [log], days: [monday]) == 0.5)
    }
}

@Suite struct PlanItemParserTests {
    @Test func medicationWithFrequencyAndDuration() throws {
        let draft = try #require(PlanItemParser.parse("Ibuprofen 400 mg twice a day for 5 days with food"))
        #expect(draft.kind == .medication)
        #expect(draft.title == "Ibuprofen")
        #expect(draft.dosage == "400 mg")
        #expect(draft.times == [time("08:00"), time("20:00")])
        #expect(draft.durationDays == 5)
        #expect(draft.instructions == "Take with food.")
    }

    @Test func exerciseWithSetsAndWeekdays() throws {
        let draft = try #require(PlanItemParser.parse("heel slides 3 sets of 10 every morning on Monday and Friday"))
        #expect(draft.kind == .exercise)
        #expect(draft.title == "Heel slides")
        #expect(draft.dosage == "3 sets of 10")
        #expect(draft.times == [time("08:00")])
        #expect(draft.weekdays == [1, 5])
    }

    @Test func explicitClockTimes() throws {
        let draft = try #require(PlanItemParser.parse("Metformin 500mg at 8am and 7:30 pm"))
        #expect(draft.times == [time("08:00"), time("19:30")])
        #expect(draft.dosage == "500mg")
    }

    @Test func instructionAndWeeks() throws {
        let draft = try #require(PlanItemParser.parse("Keep the leg elevated at night for 2 weeks"))
        #expect(draft.kind == .instruction)
        #expect(draft.title == "Keep the leg elevated")
        #expect(draft.times == [time("21:00")])
        #expect(draft.durationDays == 14)
    }

    @Test func emptyIsNil() {
        #expect(PlanItemParser.parse("   ") == nil)
    }
}

@Suite struct CareAssistantTests {
    private let pills = item("Ibuprofen", times: ["08:00", "20:00"])
    private let slides = item("Heel slides", kind: .exercise, times: ["09:00"])

    private var context: AssistantContext {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let visit = Appointment(clinicianID: clinician, patientID: patient, startsAt: now.addingTimeInterval(86_400), title: "Knee therapy")
        let old = Appointment(clinicianID: clinician, patientID: patient, startsAt: now.addingTimeInterval(-86_400 * 7), title: "Old", status: .completed)
        return AssistantContext(
            items: [pills, slides],
            todayTasks: DailyPlan.tasks(for: monday, items: [pills, slides], logs: []),
            appointments: [old, visit],
            now: now
        )
    }

    @Test func emergencyAlwaysWins() {
        #expect(CareAssistant.answer("I have chest pain after my ibuprofen", context: context) == .emergency)
        #expect(CareAssistant.answer("what number do I call", context: context) != .emergency)
    }

    @Test func nextAppointment() {
        guard case let .nextAppointment(visit) = CareAssistant.answer("When is my next appointment?", context: context) else {
            Issue.record("expected appointment")
            return
        }
        #expect(visit?.title == "Knee therapy")
    }

    @Test func namedItemAndMissedDose() {
        #expect(CareAssistant.answer("How do I take the ibuprofen?", context: context) == .item(pills))
        #expect(CareAssistant.answer("I forgot my Ibuprofen this morning", context: context) == .missedDose(pills))
    }

    @Test func medicinesToday() {
        guard case let .today(tasks, kind) = CareAssistant.answer("What medicine do I take today?", context: context) else {
            Issue.record("expected today")
            return
        }
        #expect(kind == .medication)
        #expect(tasks.count == 2)
    }

    @Test func unknownGoesToClinician() {
        #expect(CareAssistant.answer("Is it ok to swim?", context: context) == .unknown)
    }
}
