import Core
import Foundation
import Observation

/// Everything the patient app shows, loaded together so the three tabs always agree.
@Observable @MainActor
final class PatientModel {
    let me: Profile
    private let care: any CareRepository

    private(set) var clinicians: [Profile] = []
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

    // MARK: Loading

    func load() async {
        now = Date()
        let today = self.today
        do {
            async let contacts = care.contacts()
            async let appointments = care.appointments()
            async let items = care.planItems()
            async let logs = care.planLogs(from: today.adding(days: -7), to: today)
            async let messages = care.messages()
            self.clinicians = try await contacts.filter { $0.role == .clinician }
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
        await CareReminders.reschedule(items: items, appointments: appointments, now: now)
    }

    // MARK: Today

    var today: CalendarDate { Format.calendarDate(from: now) }

    var todayTasks: [PlanTask] {
        DailyPlan.tasks(for: today, items: items, logs: logs)
    }

    var nextTask: PlanTask? {
        DailyPlan.next(in: todayTasks, after: Format.localTime(from: now))
    }

    /// The clinician the patient talks to. The demo links one; more would get a picker.
    var clinician: Profile? { clinicians.first }

    func clinicianName(for id: UUID) -> String {
        clinicians.first { $0.id == id }?.displayName ?? "Your care team"
    }

    func toggle(_ task: PlanTask) async {
        if let log = task.log {
            logs.removeAll { $0.id == log.id }
            do {
                try await care.deleteLog(id: log.id)
            } catch {
                logs.append(log)
                errorMessage = Format.errorText(error)
            }
        } else {
            let log = PlanLog(itemID: task.item.id, patientID: me.id, dueOn: task.day, slot: task.slot)
            logs.append(log)
            do {
                try await care.save(log)
            } catch {
                logs.removeAll { $0.id == log.id }
                errorMessage = Format.errorText(error)
            }
        }
    }

    // MARK: Visits

    var upcomingVisits: [Appointment] {
        appointments
            .filter { ($0.status == .scheduled || $0.status == .requested) && !$0.isPast(now: now) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    var nextVisit: Appointment? {
        upcomingVisits.first { $0.status == .scheduled }
    }

    var pastVisits: [Appointment] {
        appointments
            .filter { $0.isPast(now: now) && $0.status != .cancelled }
            .sorted { $0.startsAt > $1.startsAt }
    }

    func prescribed(at visit: Appointment) -> [PlanItem] {
        items.filter { $0.appointmentID == visit.id }
    }

    func requestVisit(on day: Date, note: String) async -> Bool {
        guard let clinician else { return false }
        // The clinician sets the real time; the request carries the preferred day at 9 AM.
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = Appointment(
            clinicianID: clinician.id, patientID: me.id, startsAt: start, title: "Visit request",
            status: .requested, patientNote: trimmed.isEmpty ? nil : String(trimmed.prefix(1000))
        )
        do {
            try await care.save(request)
            appointments.append(request)
            return true
        } catch {
            errorMessage = Format.errorText(error)
            return false
        }
    }

    func cancelRequest(_ visit: Appointment) async {
        do {
            try await care.deleteAppointment(id: visit.id)
            appointments.removeAll { $0.id == visit.id }
        } catch {
            errorMessage = Format.errorText(error)
        }
    }

    // MARK: Messages

    /// Reminders from the clinician not yet acknowledged: shown on Today.
    var openReminders: [Message] {
        messages.filter { $0.kind == .reminder && $0.senderID != me.id && $0.readAt == nil }
    }

    var unreadCount: Int {
        messages.filter { $0.senderID != me.id && $0.readAt == nil }.count
    }

    func acknowledge(_ reminder: Message) async {
        await markRead([reminder.id])
    }

    func markThreadRead() async {
        await markRead(messages.filter { $0.senderID != me.id && $0.readAt == nil }.map(\.id))
    }

    private func markRead(_ ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        let stamp = Date()
        for index in messages.indices where ids.contains(messages[index].id) {
            messages[index].readAt = stamp
        }
        try? await care.markRead(messageIDs: ids)
    }

    func send(_ text: String) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let clinician, !body.isEmpty else { return false }
        let message = Message(clinicianID: clinician.id, patientID: me.id, senderID: me.id, body: String(body.prefix(2000)))
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

    func refreshMessages() async {
        if let latest = try? await care.messages() { messages = latest }
    }

    // MARK: Joining

    func join(code: String) async -> String? {
        do {
            _ = try await care.joinClinician(code: code)
            await load()
            return nil
        } catch {
            return Format.errorText(error)
        }
    }

    // MARK: Assistant

    var assistantContext: AssistantContext {
        AssistantContext(items: items, todayTasks: todayTasks, appointments: appointments, now: now)
    }

    func clearError() {
        errorMessage = nil
    }
}
