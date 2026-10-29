import Core
import DesignSystem
import SwiftUI
import UIKit

/// Two tabs: Schedule "who do I see, and who is asking?" and Patients "how is each one doing?".
struct ClinicianRootView: View {
    @State private var model: ClinicianModel
    @Environment(\.scenePhase) private var scenePhase
    let signOut: () async -> Void

    init(me: Profile, care: any CareRepository, signOut: @escaping () async -> Void) {
        _model = State(initialValue: ClinicianModel(me: me, care: care))
        self.signOut = signOut
    }

    var body: some View {
        Group {
            if model.hasLoaded {
                TabView {
                    NavigationStack {
                        ClinicianScheduleScreen(model: model, signOut: signOut)
                    }
                    .tabItem { Label("Schedule", systemImage: "calendar") }

                    NavigationStack {
                        ClinicianPatientsScreen(model: model)
                    }
                    .tabItem { Label("Patients", systemImage: "person.2.fill") }
                    .badge(model.totalUnread)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .dsScreen()
            }
        }
        .task { await model.load() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await model.refreshMessages()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }
}

struct ClinicianScheduleScreen: View {
    let model: ClinicianModel
    let signOut: () async -> Void
    @State private var editing: Appointment?
    @State private var isShowingAccount = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                Text(Format.longToday(model.now))
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.textSecondary)

                if let error = model.errorMessage {
                    ErrorText(error)
                }

                if !model.requests.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        SectionLabel("Visit requests")
                        ForEach(model.requests) { request in
                            RequestCard(request: request, patient: model.name(of: request.patientID)) {
                                editing = request
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    SectionLabel("Today")
                    if model.todaysVisits.isEmpty {
                        EmptyNote(symbol: "calendar", text: "No visits today.")
                            .dsCard()
                    } else {
                        visitList(model.todaysVisits, showDay: false)
                    }
                }

                if !model.comingUp.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        SectionLabel("Next two weeks")
                        visitList(model.comingUp, showDay: true)
                    }
                }
            }
            .padding(DS.Spacing.m)
        }
        .dsScreen()
        .navigationTitle("Schedule")
        .refreshable { await model.load() }
        .navigationDestination(for: UUID.self) { patientID in
            ClinicianPatientScreen(model: model, patientID: patientID)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAccount = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 24))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("My account")
            }
        }
        .sheet(item: $editing) { appointment in
            AppointmentEditor(model: model, patientID: appointment.patientID, existing: appointment)
        }
        .sheet(isPresented: $isShowingAccount) {
            ClinicianAccountSheet(model: model, signOut: signOut)
        }
    }

    private func visitList(_ visits: [Appointment], showDay: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(visits.enumerated()), id: \.element.id) { index, visit in
                if index > 0 {
                    Divider().overlay(DS.Colors.hairline).padding(.leading, DS.Spacing.m)
                }
                NavigationLink(value: visit.patientID) {
                    HStack(spacing: DS.Spacing.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            if showDay {
                                Text(Format.day(visit.startsAt))
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.textSecondary)
                            }
                            Text(Format.time(visit.startsAt))
                                .font(DS.Typography.rowTitle.monospacedDigit())
                                .foregroundStyle(DS.Colors.textPrimary)
                        }
                        .frame(minWidth: 96, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name(of: visit.patientID))
                                .font(DS.Typography.rowTitle)
                                .foregroundStyle(DS.Colors.textPrimary)
                            Text(visit.status == .completed ? "\(visit.title) · Done" : visit.title)
                                .font(DS.Typography.secondary)
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(DS.Colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(DS.Spacing.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .dsCard(padding: 0)
    }
}

private struct RequestCard: View {
    let request: Appointment
    let patient: String
    let schedule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(patient)
                    .font(DS.Typography.rowTitle)
                    .foregroundStyle(DS.Colors.textPrimary)
                Text("Would like a visit on \(Format.day(request.startsAt))")
                    .font(DS.Typography.secondary)
                    .foregroundStyle(DS.Colors.textPrimary)
                if let note = request.patientNote {
                    Text("“\(note)”")
                        .font(DS.Typography.secondary)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
            Button("Set a time", action: schedule)
                .buttonStyle(.dsPrimary)
        }
        .dsTinted(DS.Tints.visit)
    }
}

struct ClinicianAccountSheet: View {
    let model: ClinicianModel
    let signOut: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(model.me.displayName)
                            .font(DS.Typography.title)
                            .foregroundStyle(DS.Colors.textPrimary)
                        if let clinic = model.me.clinicName {
                            Text(clinic)
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                    }
                    PatientCodeCard(code: model.me.clinicianCode)
                    Button("Sign out") { isConfirmingSignOut = true }
                        .buttonStyle(.dsDestructive)
                        .confirmationDialog("Sign out of CareHold?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                            Button("Sign out", role: .destructive) { Task { await signOut() } }
                            Button("Cancel", role: .cancel) {}
                        }
                }
                .padding(DS.Spacing.m)
            }
            .dsScreen()
            .navigationTitle("My account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

/// The code patients type once to connect. Big and spaced so it can be read aloud.
struct PatientCodeCard: View {
    let code: String?
    @State private var isCopied = false

    var body: some View {
        if let code {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                Text("Your patient code")
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Colors.textSecondary)
                Text(code.map(String.init).joined(separator: " "))
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .textSelection(.enabled)
                    .accessibilityLabel(code.map(String.init).joined(separator: ", "))
                Text("New patients type it once in CareHold to connect with you.")
                    .font(DS.Typography.secondary)
                    .foregroundStyle(DS.Colors.textSecondary)
                Button {
                    UIPasteboard.general.string = code
                    isCopied = true
                    AccessibilityNotification.Announcement("Code copied").post()
                } label: {
                    Label(isCopied ? "Copied" : "Copy code", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.dsSecondary)
                .task(id: isCopied) {
                    guard isCopied else { return }
                    try? await Task.sleep(for: .seconds(2))
                    isCopied = false
                }
            }
            .dsCard()
        }
    }
}
