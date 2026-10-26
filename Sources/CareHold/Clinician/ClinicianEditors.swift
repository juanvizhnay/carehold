import Core
import DesignSystem
import SwiftUI

// MARK: - Appointment

/// Create a visit, set the time of a request, or write the notes after it happened.
struct AppointmentEditor: View {
    let model: ClinicianModel
    let patientID: UUID
    let existing: Appointment?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var startsAt: Date
    @State private var duration: Int
    @State private var location: String
    @State private var summary: String
    @State private var isCompleted: Bool
    @State private var isSaving = false
    @State private var isConfirmingCancel = false
    @FocusState private var focusedTitle: Bool

    init(model: ClinicianModel, patientID: UUID, existing: Appointment?) {
        self.model = model
        self.patientID = patientID
        self.existing = existing
        let defaultStart = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime
        ) ?? Date()
        let isRequest = existing?.status == .requested
        _title = State(initialValue: isRequest ? "Appointment" : existing?.title ?? "Appointment")
        _startsAt = State(initialValue: existing?.startsAt ?? defaultStart)
        _duration = State(initialValue: existing?.durationMinutes ?? 45)
        _location = State(initialValue: existing?.location ?? model.me.clinicName ?? "")
        _summary = State(initialValue: existing?.visitSummary ?? "")
        _isCompleted = State(initialValue: existing?.status == .completed)
    }

    private var isRequest: Bool { existing?.status == .requested }
    private var isPast: Bool { startsAt < Date() }

    var body: some View {
        NavigationStack {
            Form {
                if isRequest, let existing {
                    Section {
                        Text("\(model.name(of: patientID)) asked for \(Format.day(existing.startsAt)).")
                        if let note = existing.patientNote {
                            Text("“\(note)”").foregroundStyle(DS.Colors.textSecondary)
                        }
                    }
                }
                Section("Visit") {
                    TextField("Title", text: $title)
                        .focused($focusedTitle)
                    DatePicker("Starts", selection: $startsAt)
                    Picker("Length", selection: $duration) {
                        ForEach([30, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    TextField("Place", text: $location, axis: .vertical)
                }
                if isPast || existing?.status == .completed {
                    Section {
                        Toggle("Visit happened", isOn: $isCompleted)
                            .tint(DS.Colors.accent)
                        TextField("What you'd like them to remember", text: $summary, axis: .vertical)
                            .lineLimit(4...12)
                    } header: {
                        Text("Notes for the patient")
                    } footer: {
                        Text("They see these notes under Past visits, with read-aloud. Plain words work best.")
                    }
                }
                if let existing {
                    Section {
                        Button(isRequest ? "Decline request" : "Cancel visit", role: .destructive) {
                            isConfirmingCancel = true
                        }
                        .confirmationDialog(isRequest ? "Decline this request?" : "Cancel this visit?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
                            Button(isRequest ? "Decline" : "Cancel visit", role: .destructive) {
                                Task {
                                    var cancelled = existing
                                    cancelled.status = .cancelled
                                    let done = isRequest ? await model.delete(existing) : await model.save(cancelled)
                                    if done { dismiss() }
                                }
                            }
                            Button("Keep", role: .cancel) {}
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .dsScreen()
            .navigationTitle(existing == nil ? "New visit" : isRequest ? "Set a time" : "Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isRequest ? "Confirm" : "Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { if existing == nil { focusedTitle = true } }
        }
    }

    private func save() {
        isSaving = true
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let appointment = Appointment(
            id: existing?.id ?? EntityID.make(),
            clinicianID: model.me.id,
            patientID: patientID,
            startsAt: startsAt,
            durationMinutes: duration,
            title: String(title.trimmingCharacters(in: .whitespaces).prefix(120)),
            location: trimmedLocation.isEmpty ? nil : String(trimmedLocation.prefix(200)),
            status: isCompleted ? .completed : .scheduled,
            visitSummary: trimmedSummary.isEmpty ? nil : String(trimmedSummary.prefix(4000)),
            patientNote: existing?.patientNote
        )
        Task {
            if await model.save(appointment) { dismiss() }
            isSaving = false
        }
    }
}

// MARK: - Plan item

/// Add or edit a medicine, exercise or instruction. The clinician can describe it in one
/// sentence ("Ibuprofen 400 mg twice a day for 5 days") and review the filled-in fields.
struct PlanItemEditor: View {
    let model: ClinicianModel
    let patientID: UUID
    let existing: PlanItem?

    @Environment(\.dismiss) private var dismiss
    @State private var sentence = ""
    @State private var isReading = false
    @State private var readFailed = false
    @State private var kind: PlanItem.Kind
    @State private var title: String
    @State private var dosage: String
    @State private var instructions: String
    @State private var times: [Date]
    @State private var weekdays: Set<Int>
    @State private var startDate: Date
    @State private var hasEnd: Bool
    @State private var endDate: Date
    @State private var visitID: UUID?
    @State private var isSaving = false
    @State private var isConfirmingStop = false
    @FocusState private var focusedSentence: Bool

    init(model: ClinicianModel, patientID: UUID, existing: PlanItem?) {
        self.model = model
        self.patientID = patientID
        self.existing = existing
        _kind = State(initialValue: existing?.kind ?? .medication)
        _title = State(initialValue: existing?.title ?? "")
        _dosage = State(initialValue: existing?.dosage ?? "")
        _instructions = State(initialValue: existing?.instructions ?? "")
        _times = State(initialValue: (existing?.times ?? []).map(Self.date(from:)))
        _weekdays = State(initialValue: existing?.weekdays ?? [])
        _startDate = State(initialValue: existing.map { Format.calendarDate($0.startDate) } ?? Date())
        _hasEnd = State(initialValue: existing?.endDate != nil)
        _endDate = State(initialValue: existing?.endDate.map(Format.calendarDate) ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        // New items link to the most recent visit by default: "prescribed at this visit".
        let latestVisit = model.visits(of: patientID).past.first?.id
        _visitID = State(initialValue: existing == nil ? latestVisit : existing?.appointmentID)
    }

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Section {
                        TextField("e.g. Ibuprofen 400 mg twice a day for 5 days with food", text: $sentence, axis: .vertical)
                            .lineLimit(2...4)
                            .focused($focusedSentence)
                            .submitLabel(.done)
                        Button {
                            fill()
                        } label: {
                            if isReading {
                                ProgressView()
                            } else {
                                Label("Fill in from this sentence", systemImage: DS.Symbols.ask)
                            }
                        }
                        .disabled(sentence.trimmingCharacters(in: .whitespaces).isEmpty || isReading)
                    } header: {
                        Text("Describe it in one sentence")
                    } footer: {
                        Text(readFailed
                            ? "Couldn't read that one. Please fill in the fields below."
                            : "Read on this iPhone. Check the fields below before saving.")
                    }
                }

                Section("What") {
                    Picker("Type", selection: $kind) {
                        ForEach(PlanItem.Kind.allCases, id: \.self) { Text(Format.kind($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField(kind == .medication ? "Medicine name" : "Name", text: $title)
                    TextField(kind == .medication ? "Dose, e.g. 400 mg, 1 tablet" : "Amount, e.g. 3 sets of 10", text: $dosage)
                    TextField("How to do it (the patient sees this)", text: $instructions, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    ForEach(times.indices, id: \.self) { index in
                        DatePicker("Time \(index + 1)", selection: $times[index], displayedComponents: .hourAndMinute)
                    }
                    .onDelete { times.remove(atOffsets: $0) }
                    Button {
                        times.append(Self.date(from: LocalTime(hour: times.isEmpty ? 8 : 20, minute: 0)!))
                    } label: {
                        Label("Add a time", systemImage: "plus")
                    }
                    WeekdayPicker(selection: $weekdays)
                } header: {
                    Text("When")
                } footer: {
                    Text(times.isEmpty ? "No time: it shows as \"Anytime today\"." : "Swipe a time to remove it.")
                }

                Section("For how long") {
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    Toggle("Has an end date", isOn: $hasEnd)
                        .tint(DS.Colors.accent)
                    if hasEnd {
                        DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }

                let visits = model.visits(of: patientID)
                let options = (visits.past + visits.upcoming).filter { $0.status != .requested }
                if !options.isEmpty {
                    Section {
                        Picker("Prescribed at", selection: $visitID) {
                            Text("No visit").tag(UUID?.none)
                            ForEach(options) { visit in
                                Text("\(Format.shortDay(visit.startsAt)) · \(visit.title)").tag(UUID?.some(visit.id))
                            }
                        }
                    } footer: {
                        Text("The patient finds it under that visit too.")
                    }
                }

                if existing != nil {
                    Section {
                        Button("Remove from plan", role: .destructive) { isConfirmingStop = true }
                            .confirmationDialog("Remove it from the plan?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
                                Button("Remove", role: .destructive) { save(archive: true) }
                                Button("Keep", role: .cancel) {}
                            }
                    } footer: {
                        Text("Past check-offs are kept.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .dsScreen()
            .navigationTitle(existing == nil ? "Add to plan" : "Edit plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(archive: false) }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { if existing == nil { focusedSentence = true } }
        }
    }

    private func fill() {
        focusedSentence = false
        isReading = true
        readFailed = false
        let text = sentence
        Task {
            if let draft = await CareAI.draft(from: text) {
                kind = draft.kind
                title = draft.title
                dosage = draft.dosage ?? ""
                instructions = draft.instructions ?? ""
                times = draft.times.map(Self.date(from:))
                weekdays = draft.weekdays
                hasEnd = draft.durationDays != nil
                if let days = draft.durationDays {
                    endDate = Calendar.current.date(byAdding: .day, value: days - 1, to: startDate) ?? endDate
                }
            } else {
                readFailed = true
            }
            isReading = false
        }
    }

    private func save(archive: Bool) {
        isSaving = true
        func clean(_ text: String, _ limit: Int) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(limit))
        }
        let start = Format.calendarDate(from: startDate)
        let end = hasEnd ? max(Format.calendarDate(from: endDate), start) : nil
        let item = PlanItem(
            id: existing?.id ?? EntityID.make(),
            clinicianID: model.me.id,
            patientID: patientID,
            kind: kind,
            title: clean(title, 120) ?? "",
            dosage: clean(dosage, 120),
            instructions: clean(instructions, 2000),
            times: Array(Set(times.map(Format.localTime(from:)))).sorted(),
            weekdays: weekdays.count == 7 ? [] : weekdays,
            startDate: start,
            endDate: end,
            appointmentID: visitID,
            archivedAt: archive ? Date() : existing?.archivedAt
        )
        Task {
            if await model.save(item) { dismiss() }
            isSaving = false
        }
    }

    private static func date(from time: LocalTime) -> Date {
        Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
    }
}

/// Seven toggles; none selected means every day.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(selection.isEmpty ? "Every day" : "Only on these days")
            HStack(spacing: DS.Spacing.xxs) {
                ForEach(1...7, id: \.self) { day in
                    let isOn = selection.contains(day)
                    Button {
                        if isOn { selection.remove(day) } else { selection.insert(day) }
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[day % 7])
                            .font(DS.Typography.label)
                            .foregroundStyle(isOn ? DS.Colors.onAccent : DS.Colors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(isOn ? DS.Colors.accent : DS.Colors.sunken, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[day % 7])
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, DS.Spacing.xxs)
    }
}

// MARK: - Reminder

/// A reminder shows on the patient's Today screen until they tap "Got it".
struct ReminderComposer: View {
    let model: ClinicianModel
    let patientID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSending = false
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        var list = ["Please don't forget your exercises today.", "Remember to drink plenty of water."]
        if let next = model.nextVisit(of: patientID) {
            list.insert("See you \(Format.dayAndTime(next.startsAt).lowercased()). Please wear comfortable shoes.", at: 0)
        }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Write the reminder", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focused)
                } footer: {
                    Text("\(model.name(of: patientID)) sees it at the top of Today until they tap \"Got it\".")
                }
                Section("Quick reminders") {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { text = suggestion }
                            .foregroundStyle(DS.Colors.textPrimary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .dsScreen()
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        isSending = true
                        Task {
                            if await model.send(text, to: patientID, kind: .reminder) { dismiss() }
                            isSending = false
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
            .onAppear { focused = true }
        }
    }
}
