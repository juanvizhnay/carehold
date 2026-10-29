import Core
import DesignSystem
import SwiftUI

/// "Ask a question": answers come only from the patient's own plan. Rules answer the common
/// questions on every iPhone; Apple Intelligence answers the rest on the device. Anything
/// neither can answer goes to the care team in one tap, and emergencies always mean 911.
struct AskSheet: View {
    let model: PatientModel
    let openMessages: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var question = ""
    @State private var asked: String?
    @State private var reply: Reply?
    @State private var isThinking = false
    @State private var sentToClinician = false
    @State private var selectedItem: PlanItem?
    @FocusState private var focused: Bool

    private enum Reply: Equatable {
        case emergency
        case text(String, items: [PlanItem])
        /// Neither the rules nor the model could answer from the plan.
        case unsure
    }

    private let suggestions = [
        "What do I take today?",
        "When is my next visit?",
        "What exercises are left today?",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        Text("What would you like to know?")
                            .font(DS.Typography.title)
                            .foregroundStyle(DS.Colors.textPrimary)
                        Text("Type, or tap the microphone on the keyboard to speak.")
                            .font(DS.Typography.secondary)
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                    TextField("Question", text: $question, prompt: dsPrompt("Type your question here, like “how do I do the heel slides?”"), axis: .vertical)
                        .textFieldStyle(.ds)
                        .lineLimit(1...4)
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit { ask(question) }
                    Button("Ask") { ask(question) }
                        .buttonStyle(.dsPrimary(isLoading: isThinking))
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)

                    if let reply {
                        answer(reply)
                    } else {
                        VStack(alignment: .leading, spacing: DS.Spacing.s) {
                            SectionLabel("You can ask")
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    question = suggestion
                                    ask(suggestion)
                                }
                                .buttonStyle(.dsSecondary)
                            }
                        }
                    }
                }
                .padding(DS.Spacing.m)
            }
            .dsScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .font(DS.Typography.label)
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            PlanItemDetailSheet(item: item, task: nil, model: model)
        }
        .onAppear { focused = true }
        .onDisappear { Speaker.shared.stop() }
    }

    // MARK: Answer

    @ViewBuilder
    private func answer(_ reply: Reply) -> some View {
        switch reply {
        case .emergency:
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                Label("If this is an emergency, call 911 now.", systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Typography.rowTitle)
                    .foregroundStyle(DS.Colors.critical)
                Text("Don't wait for a message. If you are not sure, it is always fine to call.")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.textPrimary)
                Button {
                    if let url = URL(string: "tel://911") { openURL(url) }
                } label: {
                    Label("Call 911", systemImage: "phone.fill")
                }
                .buttonStyle(.dsPrimary)
            }
            .dsTinted(DS.Tint(fill: DS.Colors.criticalSoft, ink: DS.Colors.critical))

        case let .text(text, items):
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                Text(text)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                ReadAloudButton(text: text, id: "answer")
            }
            .dsCard()
            ForEach(items) { item in
                Button {
                    selectedItem = item
                } label: {
                    HStack(spacing: DS.Spacing.s) {
                        TintIcon(kind: item.kind)
                        Text(item.title)
                            .font(DS.Typography.rowTitle)
                            .foregroundStyle(DS.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                    .dsCard(padding: DS.Spacing.s)
                }
                .buttonStyle(.plain)
            }
            askClinician(prompt: "Still have a question?")

        case .unsure:
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                Text("I'm not sure about that one.")
                    .font(DS.Typography.rowTitle)
                    .foregroundStyle(DS.Colors.textPrimary)
                Text("Your care plan doesn't say. \(clinicianName) can answer it.")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .dsCard()
            askClinician(prompt: nil)
        }
    }

    @ViewBuilder
    private func askClinician(prompt: String?) -> some View {
        if model.clinician != nil, let asked {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                if let prompt {
                    SectionLabel(prompt)
                }
                if sentToClinician {
                    Label("Sent to \(clinicianName). You'll see the answer in Messages.", systemImage: "checkmark.circle.fill")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.accent)
                    Button("Open Messages") {
                        dismiss()
                        openMessages()
                    }
                    .buttonStyle(.dsSecondary)
                } else {
                    Button {
                        Task { sentToClinician = await model.send(asked) }
                    } label: {
                        Label("Send this question to \(clinicianName)", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.dsPrimary)
                }
            }
        }
    }

    private var clinicianName: String {
        model.clinician?.displayName ?? "Your care team"
    }

    // MARK: Asking

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        focused = false
        Speaker.shared.stop()
        asked = trimmed
        sentToClinician = false
        let context = model.assistantContext
        let rule = CareAssistant.answer(trimmed, context: context)
        if let reply = Self.reply(for: rule, clinician: clinicianName) {
            self.reply = reply
            return
        }
        // The rules didn't understand: let the on-device model try, grounded on the plan.
        guard CareAI.isAvailable else {
            reply = .unsure
            return
        }
        isThinking = true
        Task {
            let facts = CareFacts.text(context: context, summaries: model.pastVisits)
            if let text = await CareAI.answer(trimmed, facts: facts, clinicianName: clinicianName), !text.isEmpty {
                reply = .text(text, items: [])
            } else {
                reply = .unsure
            }
            isThinking = false
        }
    }

    /// Plain sentences for the rule-based answers. Nil means "not understood".
    private static func reply(for answer: AssistantAnswer, clinician: String) -> Reply? {
        switch answer {
        case .emergency:
            return .emergency

        case let .nextAppointment(visit):
            guard let visit else {
                return .text("You don't have a visit scheduled right now. You can ask for one in Visits.", items: [])
            }
            var text = "Your next visit is \(Format.dayAndTime(visit.startsAt)): \(visit.title)."
            if let location = visit.location { text += " It's at \(location)." }
            return .text(text, items: [])

        case let .today(tasks, kind):
            let what = kind.map { Format.kindPlural($0).lowercased() } ?? "things"
            guard !tasks.isEmpty else {
                return .text("You have no more \(what) for today. Everything is done.", items: [])
            }
            let lines = tasks.map { task in
                let time = task.slot.map(Format.time) ?? "anytime"
                return "\(task.item.title)\(task.item.dosage.map { ", \($0)" } ?? ""), \(time)"
            }
            let intro = tasks.count == 1 ? "There is 1 more for today:" : "There are \(tasks.count) more for today:"
            var seen = Set<UUID>()
            let items = tasks.map(\.item).filter { seen.insert($0.id).inserted }
            return .text(intro + "\n" + lines.map { "• \($0)" }.joined(separator: "\n"), items: items)

        case let .item(item):
            var text = "\(item.title): \(Format.schedule(item).lowercased())."
            if let dosage = item.dosage { text += " \(item.kind == .medication ? "Dose" : "Amount"): \(dosage)." }
            if let instructions = item.instructions { text += "\n\n\(instructions)" }
            return .text(text, items: [item])

        case let .missedDose(item):
            let name = item.map { " your \($0.title)" } ?? " a dose"
            return .text(
                "If you missed\(name), don't take extra to make up for it unless \(clinician) told you to. Send them a message and they'll tell you what to do.",
                items: item.map { [$0] } ?? []
            )

        case .unknown:
            return nil
        }
    }
}
