import Core
import Foundation
import Observation

/// The clinician's practice: their patients and everything shared with them.
@Observable @MainActor
final class ClinicianModel {
    let me: Profile
    private let care: any CareRepository

    private(set) var patients: [Profile] = []
    private(set) var appointments: [Appointment] = []
    private(set) var items: [PlanItem] = []
    private(set) var logs: [PlanLog] = []
    private(set) var messages: [Message] = []
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var now = Date()

    init(me: Profile, care: any CareRepository) {
        self.me = me
        self.care = care
    }

    func load() async {
        now = Date()
        let today = self.today
        do {
            async let contacts = care.contacts()
            async let appointments = care.appointments()
            async let items = care.planItems()
            async let logs = care.planLogs(from: today.adding(days: -6), to: today)
            async let messages = care.messages()
            self.patients = try await contacts.filter { $0.role == .patient }
            self.appointments = try await appointments
            self.items = try await items
            self.logs = try await logs
            self.messages = try await messages
            errorMessage = nil
        } catch let error as CareError {
            errorMessage = Format.errorText(error)
        } catch {
            errorMessage = Format.errorText(.unknown)
        }
        hasLoaded = true
    }

    func refreshMessages() async {
        if let latest = try? await care.messages() { messages = latest }
    }

    var today: CalendarDate { Format.calendarDate(from: now) }

    func patient(_ id: UUID) -> Profile? {
        patients.first { $0.id == id }
    }

    func name(of patientID: UUID) -> String {
        patient(patientID)?.displayName ?? "Patient"
    }

    // MARK: Schedule

    var requests: [Appointment] {
        appointments.filter { $0.status == .requested }.sorted { $0.startsAt < $1.startsAt }
    }

    var todaysVisits: [Appointment] {
        appointments
            .filter { $0.status != .requested && $0.status != .cancelled && Calendar.current.isDate($0.startsAt, inSameDayAs: now) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    /// Scheduled visits after today, for the next two weeks.
    var comingUp: [Appointment] {
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let limit = calendar.date(byAdding: .day, value: 14, to: tomorrow) ?? tomorrow
        return appointments
            .filter { $0.status == .scheduled && $0.startsAt >= tomorrow && $0.startsAt < limit }
            .sorted { $0.startsAt < $1.startsAt }
    }

    // MARK: Per patient

    func visits(of patientID: UUID) -> (upcoming: [Appointment], past: [Appointment]) {
        let mine = appointments.filter { $0.patientID == patientID && $0.status != .cancelled }
        let upcoming = mine.filter { !$0.isPast(now: now) }.sorted { $0.startsAt < $1.startsAt }
        let past = mine.filter { $0.isPast(now: now) }.sorted { $0.startsAt > $1.startsAt }
        return (upcoming, past)
    }

    func activeItems(of patientID: UUID) -> [PlanItem] {
        items.filter { $0.patientID == patientID && $0.archivedAt == nil && ($0.endDate.map { $0 >= today } ?? true) }
    }

    func todayTasks(of patientID: UUID) -> [PlanTask] {
        DailyPlan.tasks(for: today, items: items.filter { $0.patientID == patientID }, logs: logs)
    }

    /// Share of the last 7 days' tasks the patient checked off.
    func weeklyAdherence(of patientID: UUID) -> Double? {
        let days = (0..<7).map { today.adding(days: -$0) }
        return DailyPlan.adherence(items: items.filter { $0.patientID == patientID }, logs: logs, days: days)
    }

    func thread(with patientID: UUID) -> [Message] {
        messages.filter { $0.patientID == patientID }
    }

    func unreadCount(from patientID: UUID) -> Int {
        messages.filter { $0.patientID == patientID && $0.senderID == patientID && $0.readAt == nil }.count
    }

    var totalUnread: Int {
        messages.filter { $0.senderID != me.id && $0.readAt == nil }.count
    }

    func nextVisit(of patientID: UUID) -> Appointment? {
        visits(of: patientID).upcoming.first { $0.status == .scheduled }
    }

    // MARK: Writes

    func save(_ appointment: Appointment) async -> Bool {
        do {
            try await care.save(appointment)
            appointments.removeAll { $0.id == appointment.id }
            appointments.append(appointment)
            return true
        } catch {
            errorMessage = Format.errorText(error)
            return false
        }
    }

    func delete(_ appointment: Appointment) async -> Bool {
        do {
            try await care.deleteAppointment(id: appointment.id)
            appointments.removeAll { $0.id == appointment.id }
            return true
        } catch {
            errorMessage = Format.errorText(error)
            return false
        }
    }

    func save(_ item: PlanItem) async -> Bool {
        do {
            try await care.save(item)
            items.removeAll { $0.id == item.id }
            items.append(item)
            return true
        } catch {
            errorMessage = Format.errorText(error)
            return false
        }
    }

    func send(_ text: String, to patientID: UUID, kind: Message.Kind = .message) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        let message = Message(clinicianID: me.id, patientID: patientID, senderID: me.id, kind: kind, body: String(body.prefix(2000)))
        messages.append(message)
        do {
            try await care.send(message)
            return true
        } catch {
            messages.removeAll { $0.id == message.id }
            errorMessage = Format.errorText(error)
            return false
        }
    }

    func markRead(from patientID: UUID) async {
        let ids = messages.filter { $0.patientID == patientID && $0.senderID == patientID && $0.readAt == nil }.map(\.id)
        guard !ids.isEmpty else { return }
        let stamp = Date()
        for index in messages.indices where ids.contains(messages[index].id) {
            messages[index].readAt = stamp
        }
        try? await care.markRead(messageIDs: ids)
    }
}
