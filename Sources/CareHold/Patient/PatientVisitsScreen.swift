import Core
import DesignSystem
import SwiftUI

struct PatientVisitsScreen: View {
    let model: PatientModel
    @State private var isRequesting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    SectionLabel("Coming up")
                    if model.upcomingVisits.isEmpty {
                        EmptyNote(symbol: "calendar", text: "No visits scheduled.")
                            .dsCard()
                    } else {
                        ForEach(model.upcomingVisits) { visit in
                            UpcomingVisitRow(visit: visit, clinician: model.clinicianName(for: visit.clinicianID)) {
                                Task { await model.cancelRequest(visit) }
                            }
                        }
                    }
                    if model.clinician != nil {
                        Button {
                            isRequesting = true
                        } label: {
                            Label("Ask for a visit", systemImage: "plus")
                        }
                        .buttonStyle(.dsSecondary)
                    }
                }

                if !model.pastVisits.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        SectionLabel("Past visits")
                        ForEach(model.pastVisits) { visit in
                            NavigationLink(value: visit) {
                                PastVisitRow(visit: visit, prescribedCount: model.prescribed(at: visit).count)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(DS.Spacing.m)
        }
        .dsScreen()
        .navigationTitle("Visits")
        .refreshable { await model.load() }
        .navigationDestination(for: Appointment.self) { visit in
            PastVisitScreen(visit: visit, model: model)
        }
        .sheet(isPresented: $isRequesting) {
            RequestVisitSheet(model: model)
        }
    }
}

private struct UpcomingVisitRow: View {
    let visit: Appointment
    let clinician: String
    let cancel: () -> Void
    @State private var isConfirmingCancel = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .top, spacing: DS.Spacing.m) {
                TintIcon(symbol: visit.status == .requested ? "hourglass" : DS.Symbols.visit, tint: DS.Tints.visit)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    if visit.status == .requested {
                        Text("Waiting for \(clinician) to confirm")
                            .font(DS.Typography.label)
                            .foregroundStyle(DS.Tints.visit.ink)
                        Text("You asked for \(Format.day(visit.startsAt))")
                            .font(DS.Typography.rowTitle)
                            .foregroundStyle(DS.Colors.textPrimary)
                    } else {
                        Text(Format.dayAndTime(visit.startsAt))
                            .font(DS.Typography.rowTitle)
                            .foregroundStyle(DS.Colors.textPrimary)
                        Text("\(visit.title) with \(clinician)")
                            .font(DS.Typography.secondary)
                            .foregroundStyle(DS.Colors.textPrimary)
                    }
                    if let location = visit.location {
                        Text(location)
                            .font(DS.Typography.secondary)
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                    if let note = visit.patientNote {
                        Text("“\(note)”")
                            .font(DS.Typography.secondary)
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            if visit.status == .requested {
                Button("Cancel request", role: .destructive) { isConfirmingCancel = true }
                    .buttonStyle(.dsSecondary)
                    .confirmationDialog("Cancel this request?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
                        Button("Cancel request", role: .destructive, action: cancel)
                        Button("Keep it", role: .cancel) {}
                    }
            }
        }
        .dsTinted(DS.Tints.visit)
    }
}

private struct PastVisitRow: View {
    let visit: Appointment
    let prescribedCount: Int

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(Format.shortDay(visit.startsAt))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.textSecondary)
                Text(visit.title)
                    .font(DS.Typography.rowTitle)
                    .foregroundStyle(DS.Colors.textPrimary)
                if visit.visitSummary != nil || prescribedCount > 0 {
                    Text(details)
                        .font(DS.Typography.secondary)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(DS.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .dsCard()
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts: [String] = []
        if visit.visitSummary != nil { parts.append("Notes") }
        if prescribedCount > 0 { parts.append(prescribedCount == 1 ? "1 thing to do" : "\(prescribedCount) things to do") }
        return parts.joined(separator: " · ")
    }
}

/// What the therapist said and prescribed at a past visit.
struct PastVisitScreen: View {
    let visit: Appointment
    let model: PatientModel
    @State private var selected: PlanItem?
    @State private var simpler: String?
    @State private var isSimplifying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(Format.day(visit.startsAt))
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.textSecondary)
                    Text(visit.title)
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Colors.textPrimary)
                    Text("With \(model.clinicianName(for: visit.clinicianID))")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.textSecondary)
                }

                if let summary = visit.visitSummary {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        SectionLabel("What we talked about")
                        Text(simpler ?? summary)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        if simpler != nil {
                            Text("Simpler words by Apple Intelligence on this iPhone. Your therapist's note is the one that counts.")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                    }
                    .dsCard()
                    ReadAloudButton(text: simpler ?? summary, id: "visit-\(visit.id)")
                    if CareAI.isAvailable && simpler == nil {
                        Button {
                            isSimplifying = true
                            Task {
                                simpler = await CareAI.simplify(summary)
                                isSimplifying = false
                            }
                        } label: {
                            if isSimplifying {
                                ProgressView()
                            } else {
                                Label("Explain in simpler words", systemImage: DS.Symbols.ask)
                            }
                        }
                        .buttonStyle(.dsSecondary)
                        .disabled(isSimplifying)
                    }
                }

                let prescribed = model.prescribed(at: visit)
                if !prescribed.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        SectionLabel("Prescribed at this visit")
                        ForEach(prescribed) { item in
                            Button {
                                selected = item
                            } label: {
                                HStack(spacing: DS.Spacing.s) {
                                    TintIcon(kind: item.kind)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(DS.Typography.rowTitle)
                                            .foregroundStyle(DS.Colors.textPrimary)
                                        Text(item.dosage.map { "\($0) · \(Format.schedule(item))" } ?? Format.schedule(item))
                                            .font(DS.Typography.secondary)
                                            .foregroundStyle(DS.Colors.textSecondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(DS.Colors.textSecondary)
                                        .accessibilityHidden(true)
                                }
                                .dsCard(padding: DS.Spacing.s)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(DS.Spacing.m)
        }
        .dsScreen()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { item in
            PlanItemDetailSheet(item: item, task: nil, model: model)
        }
        .onDisappear { Speaker.shared.stop() }
    }
}

struct RequestVisitSheet: View {
    let model: PatientModel
    @Environment(\.dismiss) private var dismiss
    @State private var day = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var note = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    Text("\(model.clinician?.displayName ?? "Your therapist") will confirm the time with you.")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.textSecondary)
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        SectionLabel("Which day suits you?")
                        DatePicker("Day", selection: $day, in: Date()..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .dsCard(padding: DS.Spacing.xs)
                    }
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        SectionLabel("Anything they should know? (optional)")
                        TextField("For example: my knee hurts more", text: $note, axis: .vertical)
                            .textFieldStyle(.ds)
                            .lineLimit(2...5)
                    }
                    Button("Send request") {
                        isSending = true
                        Task {
                            if await model.requestVisit(on: day, note: note) { dismiss() }
                            isSending = false
                        }
                    }
                    .buttonStyle(.dsPrimary(isLoading: isSending))
                    .disabled(isSending)
                }
                .padding(DS.Spacing.m)
            }
            .dsScreen()
            .navigationTitle("Ask for a visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(DS.Typography.label)
                }
            }
        }
    }
}
