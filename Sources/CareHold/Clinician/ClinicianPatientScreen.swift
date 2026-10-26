import Core
import DesignSystem
import SwiftUI

/// One patient: what they do today, their plan, their visits and the conversation.
struct ClinicianPatientScreen: View {
    let model: ClinicianModel
    let patientID: UUID

    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        case newVisit
        case visit(Appointment)
        case newItem
        case item(PlanItem)
        case reminder

        var id: String {
            switch self {
            case .newVisit: "new-visit"
            case .visit(let visit): "visit-\(visit.id)"
            case .newItem: "new-item"
            case .item(let item): "item-\(item.id)"
            case .reminder: "reminder"
            }
        }
    }

    var body: some View {
        let patient = model.patient(patientID)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                HStack(spacing: DS.Spacing.m) {
                    Initials(name: patient?.displayName ?? "")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(patient?.displayName ?? "Patient")
                            .font(DS.Typography.title)
                            .foregroundStyle(DS.Colors.textPrimary)
                        if let adherence = model.weeklyAdherence(of: patientID) {
                            Text("\(Int((adherence * 100).rounded()))% of the plan done in the last 7 days")
                                .font(DS.Typography.secondary)
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                    }
                }

                actions

                if let error = model.errorMessage {
                    ErrorText(error)
                }

                todaySection
                planSection
                visitsSection
            }
            .padding(DS.Spacing.m)
        }
        .dsScreen()
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newVisit:
                AppointmentEditor(model: model, patientID: patientID, existing: nil)
            case .visit(let visit):
                AppointmentEditor(model: model, patientID: patientID, existing: visit)
            case .newItem:
                PlanItemEditor(model: model, patientID: patientID, existing: nil)
            case .item(let item):
                PlanItemEditor(model: model, patientID: patientID, existing: item)
            case .reminder:
                ReminderComposer(model: model, patientID: patientID)
            }
        }
    }

    private var actions: some View {
        let unread = model.unreadCount(from: patientID)
        return Grid(horizontalSpacing: DS.Spacing.s, verticalSpacing: DS.Spacing.s) {
            GridRow {
                NavigationLink {
                    ClinicianThreadScreen(model: model, patientID: patientID)
                } label: {
                    Label(unread > 0 ? "Messages (\(unread))" : "Messages", systemImage: DS.Symbols.message)
                }
                .buttonStyle(.dsPrimary)
                Button { sheet = .reminder } label: {
                    Label("Reminder", systemImage: DS.Symbols.reminder)
                }
                .buttonStyle(.dsSecondary)
            }
            GridRow {
                Button { sheet = .newItem } label: {
                    Label("Add to plan", systemImage: "plus")
                }
                .buttonStyle(.dsSecondary)
                Button { sheet = .newVisit } label: {
                    Label("New visit", systemImage: DS.Symbols.visit)
                }
                .buttonStyle(.dsSecondary)
            }
        }
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private var todaySection: some View {
        let tasks = model.todayTasks(of: patientID)
        if !tasks.isEmpty {
            let done = tasks.filter(\.isDone).count
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                SectionLabel("Today: \(done) of \(tasks.count) done")
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(tasks) { task in
                        HStack(spacing: DS.Spacing.s) {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.isDone ? DS.Colors.accent : DS.Colors.textSecondary)
                                .font(.title3)
                                .accessibilityHidden(true)
                            Text(task.item.title)
                                .font(DS.Typography.secondary)
                                .foregroundStyle(DS.Colors.textPrimary)
                            Spacer()
                            Text(task.slot.map(Format.time) ?? "Anytime")
                                .font(DS.Typography.secondary.monospacedDigit())
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(task.item.title), \(task.slot.map(Format.time) ?? "anytime"), \(task.isDone ? "done" : "not done")")
                    }
                }
                .dsCard()
            }
        }
    }

    private var planSection: some View {
        let items = model.activeItems(of: patientID)
        return VStack(alignment: .leading, spacing: DS.Spacing.s) {
            SectionLabel("Care plan")
            if items.isEmpty {
                EmptyNote(symbol: "list.bullet.clipboard", text: "Nothing in the plan yet.")
                    .dsCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().overlay(DS.Colors.hairline).padding(.leading, 76)
                        }
                        Button { sheet = .item(item) } label: {
                            HStack(spacing: DS.Spacing.s) {
                                TintIcon(kind: item.kind)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(DS.Typography.rowTitle)
                                        .foregroundStyle(DS.Colors.textPrimary)
                                    Text([item.dosage, Format.schedule(item)].compactMap { $0 }.joined(separator: " · "))
                                        .font(DS.Typography.secondary)
                                        .foregroundStyle(DS.Colors.textSecondary)
                                        .multilineTextAlignment(.leading)
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
    }

    private var visitsSection: some View {
        let visits = model.visits(of: patientID)
        return VStack(alignment: .leading, spacing: DS.Spacing.s) {
            SectionLabel("Visits")
            if visits.upcoming.isEmpty && visits.past.isEmpty {
                EmptyNote(symbol: "calendar", text: "No visits yet.")
                    .dsCard()
            } else {
                VStack(spacing: 0) {
                    let all = visits.upcoming + visits.past
                    ForEach(Array(all.enumerated()), id: \.element.id) { index, visit in
                        if index > 0 {
                            Divider().overlay(DS.Colors.hairline).padding(.leading, DS.Spacing.m)
                        }
                        Button { sheet = .visit(visit) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(visit.status == .requested ? "Requested for \(Format.day(visit.startsAt))" : Format.dayAndTime(visit.startsAt))
                                        .font(DS.Typography.rowTitle)
                                        .foregroundStyle(DS.Colors.textPrimary)
                                    Text(status(of: visit))
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
    }

    private func status(of visit: Appointment) -> String {
        switch visit.status {
        case .requested: "Waiting for you to set a time"
        case .scheduled: visit.isPast(now: model.now) ? "\(visit.title) · Add notes" : visit.title
        case .completed: visit.visitSummary == nil ? "\(visit.title) · Done" : "\(visit.title) · Notes shared"
        case .cancelled: "\(visit.title) · Cancelled"
        }
    }
}

struct ClinicianThreadScreen: View {
    let model: ClinicianModel
    let patientID: UUID

    var body: some View {
        let name = model.name(of: patientID)
        ChatThread(
            messages: model.thread(with: patientID),
            myID: model.me.id,
            otherName: name,
            placeholder: "Write to \(name)",
            send: { await model.send($0, to: patientID) }
        )
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.thread(with: patientID).count) { await model.markRead(from: patientID) }
    }
}
