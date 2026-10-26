import Core
import Foundation
import Supabase

/// Row level security decides what each query returns; the queries never filter by "me"
/// for safety, only for meaning (e.g. the unread messages addressed to me).
actor SupabaseCareRepository: CareRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    private func userID() async throws(CareError) -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch {
            throw .notAllowed
        }
    }

    // MARK: Profiles

    func myProfile() async throws(CareError) -> Profile {
        let id = try await userID()
        return try await run {
            let row: ProfileDTO = try await client.from("profiles").select().eq("id", value: id).single().execute().value
            return row.domain
        }
    }

    func updateMyProfile(fullName: String, phone: String?) async throws(CareError) {
        let id = try await userID()
        struct Update: Encodable {
            let full_name: String
            let phone: String?
        }
        try await run {
            _ = try await client.from("profiles")
                .update(Update(full_name: fullName, phone: phone))
                .eq("id", value: id)
                .execute()
        }
    }

    func contacts() async throws(CareError) -> [Profile] {
        let id = try await userID()
        return try await run {
            let rows: [ProfileDTO] = try await client.from("profiles").select().neq("id", value: id)
                .order("full_name").execute().value
            return rows.map(\.domain)
        }
    }

    func joinClinician(code: String) async throws(CareError) -> UUID {
        do {
            return try await client.rpc("join_clinician", params: ["p_code": code]).execute().value
        } catch {
            if let error = error as? PostgrestError, error.code == "P0002" { throw .codeNotFound }
            throw map(error)
        }
    }

    // MARK: Appointments

    func appointments() async throws(CareError) -> [Appointment] {
        try await run {
            let rows: [AppointmentDTO] = try await client.from("appointments").select().order("starts_at").execute().value
            return rows.map(\.domain)
        }
    }

    func save(_ appointment: Appointment) async throws(CareError) {
        try await run {
            let updated: [IDRow] = try await client.from("appointments")
                .update(AppointmentUpdate(appointment))
                .eq("id", value: appointment.id)
                .select("id")
                .execute().value
            if updated.isEmpty {
                _ = try await client.from("appointments").insert(AppointmentDTO(appointment), returning: .minimal).execute()
            }
        }
    }

    func deleteAppointment(id: UUID) async throws(CareError) {
        try await run {
            _ = try await client.from("appointments").delete().eq("id", value: id).execute()
        }
    }

    // MARK: Plan

    func planItems() async throws(CareError) -> [PlanItem] {
        try await run {
            let rows: [PlanItemDTO] = try await client.from("plan_items").select().order("created_at").execute().value
            return rows.compactMap(\.domain)
        }
    }

    func save(_ item: PlanItem) async throws(CareError) {
        try await run {
            let updated: [IDRow] = try await client.from("plan_items")
                .update(PlanItemUpdate(item))
                .eq("id", value: item.id)
                .select("id")
                .execute().value
            if updated.isEmpty {
                _ = try await client.from("plan_items").insert(PlanItemDTO(item), returning: .minimal).execute()
            }
        }
    }

    func planLogs(from: CalendarDate, to: CalendarDate) async throws(CareError) -> [PlanLog] {
        try await run {
            let rows: [PlanLogDTO] = try await client.from("plan_logs").select()
                .gte("due_on", value: from.isoString)
                .lte("due_on", value: to.isoString)
                .execute().value
            return rows.map(\.domain)
        }
    }

    func save(_ log: PlanLog) async throws(CareError) {
        do {
            _ = try await client.from("plan_logs").insert(PlanLogDTO(log), returning: .minimal).execute()
        } catch let error as PostgrestError where error.code == "23505" {
            // Already checked off (a retry, or another device): nothing to do.
        } catch {
            throw map(error)
        }
    }

    func deleteLog(id: UUID) async throws(CareError) {
        try await run {
            _ = try await client.from("plan_logs").delete().eq("id", value: id).execute()
        }
    }

    // MARK: Messages

    func messages() async throws(CareError) -> [Core.Message] {
        try await run {
            let rows: [MessageDTO] = try await client.from("messages").select()
                .order("created_at", ascending: false).limit(500).execute().value
            return rows.reversed().map(\.domain)
        }
    }

    func send(_ message: Core.Message) async throws(CareError) {
        try await run {
            _ = try await client.from("messages")
                .insert(MessageInsert(message), returning: .minimal)
                .execute()
        }
    }

    func markRead(messageIDs: [UUID]) async throws(CareError) {
        guard !messageIDs.isEmpty else { return }
        try await run {
            _ = try await client.from("messages")
                .update(["read_at": Date()])
                .in("id", values: messageIDs)
                .execute()
        }
    }

    // MARK: Errors

    private func run<T: Sendable>(_ work: () async throws -> T) async throws(CareError) -> T {
        do {
            return try await work()
        } catch {
            throw map(error)
        }
    }

    private func map(_ error: any Error) -> CareError {
        if let error = error as? CareError { return error }
        if error is URLError { return .network }
        if let error = error as? PostgrestError, error.code == "42501" { return .notAllowed }
        return .unknown
    }
}

// MARK: - Rows

// Updates send only the columns the database lets the app change (column-level grants);
// ids and owners are immutable, so saves are "update, else insert" instead of an upsert.

private struct IDRow: Decodable {
    let id: UUID
}

private struct AppointmentUpdate: Encodable {
    let starts_at: Date
    let duration_minutes: Int
    let title: String
    let location: String?
    let status: Appointment.Status
    let visit_summary: String?

    init(_ value: Appointment) {
        starts_at = value.startsAt
        duration_minutes = value.durationMinutes
        title = value.title
        location = value.location
        status = value.status
        visit_summary = value.visitSummary
    }

    /// Nil must reach the server as null, so clearing a field clears it.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(starts_at, forKey: .starts_at)
        try container.encode(duration_minutes, forKey: .duration_minutes)
        try container.encode(title, forKey: .title)
        try container.encode(location, forKey: .location)
        try container.encode(status, forKey: .status)
        try container.encode(visit_summary, forKey: .visit_summary)
    }

    private enum CodingKeys: String, CodingKey {
        case starts_at, duration_minutes, title, location, status, visit_summary
    }
}

private struct PlanItemUpdate: Encodable {
    let kind: PlanItem.Kind
    let title: String
    let dosage: String?
    let instructions: String?
    let times: [LocalTime]
    let weekdays: [Int]
    let start_date: CalendarDate
    let end_date: CalendarDate?
    let appointment_id: UUID?
    let archived_at: Date?

    init(_ value: PlanItem) {
        kind = value.kind
        title = value.title
        dosage = value.dosage
        instructions = value.instructions
        times = value.times
        weekdays = value.weekdays.sorted()
        start_date = value.startDate
        end_date = value.endDate
        appointment_id = value.appointmentID
        archived_at = value.archivedAt
    }

    /// Nil must reach the server as null, so clearing a field clears it.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(dosage, forKey: .dosage)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(times, forKey: .times)
        try container.encode(weekdays, forKey: .weekdays)
        try container.encode(start_date, forKey: .start_date)
        try container.encode(end_date, forKey: .end_date)
        try container.encode(appointment_id, forKey: .appointment_id)
        try container.encode(archived_at, forKey: .archived_at)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, title, dosage, instructions, times, weekdays, start_date, end_date, appointment_id, archived_at
    }
}

private struct ProfileDTO: Codable {
    let id: UUID
    let role: Role
    let full_name: String
    let clinic_name: String?
    let clinician_code: String?
    let phone: String?

    var domain: Profile {
        Profile(id: id, role: role, fullName: full_name, clinicName: clinic_name, clinicianCode: clinician_code, phone: phone)
    }
}

private struct AppointmentDTO: Codable {
    let id: UUID
    let clinician_id: UUID
    let patient_id: UUID
    let starts_at: Date
    let duration_minutes: Int
    let title: String
    let location: String?
    let status: Appointment.Status
    let visit_summary: String?
    let patient_note: String?

    init(_ value: Appointment) {
        id = value.id
        clinician_id = value.clinicianID
        patient_id = value.patientID
        starts_at = value.startsAt
        duration_minutes = value.durationMinutes
        title = value.title
        location = value.location
        status = value.status
        visit_summary = value.visitSummary
        patient_note = value.patientNote
    }

    var domain: Appointment {
        Appointment(
            id: id, clinicianID: clinician_id, patientID: patient_id, startsAt: starts_at,
            durationMinutes: duration_minutes, title: title, location: location, status: status,
            visitSummary: visit_summary, patientNote: patient_note
        )
    }
}

private struct PlanItemDTO: Codable {
    let id: UUID
    let clinician_id: UUID
    let patient_id: UUID
    let kind: PlanItem.Kind
    let title: String
    let dosage: String?
    let instructions: String?
    let times: [LocalTime]
    let weekdays: [Int]
    let start_date: CalendarDate
    let end_date: CalendarDate?
    let appointment_id: UUID?
    let archived_at: Date?

    init(_ value: PlanItem) {
        id = value.id
        clinician_id = value.clinicianID
        patient_id = value.patientID
        kind = value.kind
        title = value.title
        dosage = value.dosage
        instructions = value.instructions
        times = value.times
        weekdays = value.weekdays.sorted()
        start_date = value.startDate
        end_date = value.endDate
        appointment_id = value.appointmentID
        archived_at = value.archivedAt
    }

    var domain: PlanItem? {
        PlanItem(
            id: id, clinicianID: clinician_id, patientID: patient_id, kind: kind, title: title, dosage: dosage,
            instructions: instructions, times: times, weekdays: Set(weekdays), startDate: start_date,
            endDate: end_date, appointmentID: appointment_id, archivedAt: archived_at
        )
    }
}

private struct PlanLogDTO: Codable {
    let id: UUID
    let item_id: UUID
    let patient_id: UUID
    let due_on: CalendarDate
    let slot: LocalTime?
    let done_at: Date

    init(_ value: PlanLog) {
        id = value.id
        item_id = value.itemID
        patient_id = value.patientID
        due_on = value.dueOn
        slot = value.slot
        done_at = value.doneAt
    }

    var domain: PlanLog {
        PlanLog(id: id, itemID: item_id, patientID: patient_id, dueOn: due_on, slot: slot, doneAt: done_at)
    }
}

private struct MessageDTO: Decodable {
    let id: UUID
    let clinician_id: UUID
    let patient_id: UUID
    let sender_id: UUID
    let kind: Core.Message.Kind
    let body: String
    let created_at: Date
    let read_at: Date?

    var domain: Core.Message {
        Core.Message(
            id: id, clinicianID: clinician_id, patientID: patient_id, senderID: sender_id, kind: kind,
            body: body, createdAt: created_at, readAt: read_at
        )
    }
}

/// The server sets `created_at`; `read_at` is only ever set by the recipient.
private struct MessageInsert: Encodable {
    let id: UUID
    let clinician_id: UUID
    let patient_id: UUID
    let sender_id: UUID
    let kind: Core.Message.Kind
    let body: String

    init(_ value: Core.Message) {
        id = value.id
        clinician_id = value.clinicianID
        patient_id = value.patientID
        sender_id = value.senderID
        kind = value.kind
        body = value.body
    }
}
