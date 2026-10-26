import Core
import DesignSystem
import SwiftUI
import UserNotifications

struct PatientTodayScreen: View {
    let model: PatientModel
    let signOut: () async -> Void
    let openMessages: () -> Void

    @State private var isAsking = false
    @State private var isShowingSettings = false
    @State private var selectedTask: PlanTask?
    @State private var reminderStatus: UNAuthorizationStatus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                header
                askButton
                if let error = model.errorMessage {
                    ErrorText(error)
                }
                ForEach(model.openReminders) { reminder in
                    ReminderCard(
                        reminder: reminder,
                        from: model.clinicianName(for: reminder.clinicianID),
                        acknowledge: { Task { await model.acknowledge(reminder) } }
                    )
                }
                if let visit = model.nextVisit, visit.startsAt.timeIntervalSince(model.now) < 7 * 86_400 {
                    NextVisitCard(visit: visit, clinician: model.clinicianName(for: visit.clinicianID))
                }
                if reminderStatus == .notDetermined, model.items.contains(where: { !$0.times.isEmpty }) {
                    turnOnRemindersCard
                }
                plan
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.bottom, DS.Spacing.xl)
        }
        .dsScreen()
        .refreshable { await model.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 26))
                        .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                }
                .accessibilityLabel("My account")
            }
        }
        .sheet(isPresented: $isAsking) {
            AskSheet(model: model, openMessages: openMessages)
        }
        .sheet(isPresented: $isShowingSettings) {
            PatientSettingsSheet(model: model, signOut: signOut)
        }
        .sheet(item: $selectedTask) { task in
            PlanItemDetailSheet(item: task.item, task: task, model: model)
        }
        .task { reminderStatus = await CareReminders.status() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text("\(Format.greeting(model.now)), \(model.me.firstName)")
                .font(DS.Typography.hero)
                .foregroundStyle(DS.Colors.textPrimary)
            Text(Format.longToday(model.now))
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.textSecondary)
        }
        .padding(.top, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var askButton: some View {
        Button {
            isAsking = true
        } label: {
            HStack(spacing: DS.Spacing.m) {
                TintIcon(symbol: DS.Symbols.ask, tint: DS.Tint(fill: DS.Colors.accent, ink: DS.Colors.onAccent))
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("Ask a question")
                        .font(DS.Typography.rowTitle)
                        .foregroundStyle(DS.Colors.textPrimary)
                    Text("About your medicines, exercises or visits")
                        .font(DS.Typography.secondary)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .dsTinted(DS.Tint(fill: DS.Colors.accentSoft, ink: DS.Colors.accent))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens a place to type or say your question")
    }

    private var turnOnRemindersCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Label("Get a reminder when it's time", systemImage: DS.Symbols.reminder)
                .font(DS.Typography.rowTitle)
                .foregroundStyle(DS.Colors.textPrimary)
            Text("Your iPhone will let you know when it's time for your medicine, your exercises and your visits.")
                .font(DS.Typography.secondary)
                .foregroundStyle(DS.Colors.textSecondary)
            Button("Turn on reminders") {
                Task {
                    _ = await CareReminders.requestPermission()
                    reminderStatus = await CareReminders.status()
                    await CareReminders.reschedule(items: model.items, appointments: model.appointments)
                }
            }
            .buttonStyle(.dsPrimary)
        }
        .dsCard()
    }

    @ViewBuilder
    private var plan: some View {
        let tasks = model.todayTasks
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("Your plan for today")
                .font(DS.Typography.sectionTitle)
                .foregroundStyle(DS.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if tasks.isEmpty {
                EmptyNote(symbol: "leaf", text: "Nothing planned for today. Enjoy your day.")
                    .dsCard()
            } else {
                if tasks.allSatisfy(\.isDone) {
                    Label("All done for today. Well done.", systemImage: "checkmark.circle.fill")
                        .font(DS.Typography.rowTitle)
                        .foregroundStyle(DS.Colors.accent)
                        .dsTinted(DS.Tint(fill: DS.Colors.accentSoft, ink: DS.Colors.accent))
                }
                ForEach(DailyPlan.grouped(tasks), id: \.part) { group in
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        SectionLabel(Format.dayPart(group.part))
                        VStack(spacing: 0) {
                            ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
                                if index > 0 {
                                    Divider().overlay(DS.Colors.hairline).padding(.leading, 76)
                                }
                                TaskRow(
                                    task: task,
                                    isNext: task.id == model.nextTask?.id,
                                    open: { selectedTask = task },
                                    toggle: { Task { await model.toggle(task) } }
                                )
                            }
                        }
                        .dsCard(padding: 0)
                    }
                }
            }
        }
    }
}

/// One dose or exercise: tap the text for details, tap the circle to mark it done.
struct TaskRow: View {
    let task: PlanTask
    let isNext: Bool
    let open: () -> Void
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Button(action: open) {
                HStack(spacing: DS.Spacing.s) {
                    TintIcon(kind: task.item.kind)
                        .opacity(task.isDone ? 0.5 : 1)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(task.item.title)
                            .font(DS.Typography.rowTitle)
                            .foregroundStyle(DS.Colors.textPrimary)
                            .strikethrough(task.isDone, color: DS.Colors.textSecondary)
                        Text(subtitle)
                            .font(DS.Typography.secondary)
                            .foregroundStyle(DS.Colors.textSecondary)
                        if isNext && !task.isDone {
                            Text("Up next")
                                .font(DS.Typography.caption.weight(.semibold))
                                .foregroundStyle(DS.Colors.accent)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(task.item.title), \(subtitle)\(task.isDone ? ", done" : "")")
            .accessibilityHint("Shows how to do it")

            Button(action: toggle) {
                CheckCircle(isDone: task.isDone)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: task.isDone) { _, done in done }
            .accessibilityLabel(task.isDone ? "Done. Tap to undo" : "Mark \(task.item.title) as done")
        }
        .padding(.leading, DS.Spacing.m)
        .padding(.trailing, DS.Spacing.xs)
        .padding(.vertical, DS.Spacing.s)
    }

    private var subtitle: String {
        let time = task.slot.map(Format.time) ?? "Anytime"
        guard let dosage = task.item.dosage else { return time }
        return "\(time) · \(dosage)"
    }
}

struct ReminderCard: View {
    let reminder: Message
    let from: String
    let acknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Label("Reminder from \(from)", systemImage: DS.Symbols.reminder)
                .font(DS.Typography.label)
                .foregroundStyle(DS.Tints.reminder.ink)
            Text(reminder.body)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Spacing.s) {
                Button("Got it", action: acknowledge)
                    .buttonStyle(.dsPrimary)
                ReadAloudButton(text: reminder.body, id: reminder.id.uuidString, compact: true)
            }
        }
        .dsTinted(DS.Tints.reminder)
    }
}

struct NextVisitCard: View {
    let visit: Appointment
    let clinician: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            TintIcon(symbol: DS.Symbols.visit, tint: DS.Tints.visit)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Next visit")
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Tints.visit.ink)
                Text(Format.dayAndTime(visit.startsAt))
                    .font(DS.Typography.rowTitle)
                    .foregroundStyle(DS.Colors.textPrimary)
                Text("\(visit.title) with \(clinician)")
                    .font(DS.Typography.secondary)
                    .foregroundStyle(DS.Colors.textPrimary)
                if let location = visit.location {
                    Text(location)
                        .font(DS.Typography.secondary)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
        }
        .dsTinted(DS.Tints.visit)
        .accessibilityElement(children: .combine)
    }
}

/// "Read aloud" for any text: speaker icon plus the word, so it is never a mystery icon.
struct ReadAloudButton: View {
    let text: String
    let id: String
    var compact = false

    var body: some View {
        let isSpeaking = Speaker.shared.speakingID == id
        Button {
            Speaker.shared.toggle(text, id: id)
        } label: {
            Label(isSpeaking ? "Stop" : "Read aloud", systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
        }
        .buttonStyle(.dsSecondary)
        .frame(maxWidth: compact ? 200 : .infinity)
    }
}
