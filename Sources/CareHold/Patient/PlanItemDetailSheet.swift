import Core
import DesignSystem
import SwiftUI

/// How to take a medicine or do an exercise, in large print, with read-aloud and,
/// on iPhones with Apple Intelligence, the same note in simpler words.
struct PlanItemDetailSheet: View {
    let item: PlanItem
    /// The specific dose being looked at from Today, if any.
    let task: PlanTask?
    let model: PatientModel

    @Environment(\.dismiss) private var dismiss
    @State private var simpler: String?
    @State private var isSimplifying = false

    private var currentTask: PlanTask? {
        guard let task else { return nil }
        return model.todayTasks.first { $0.id == task.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    HStack(spacing: DS.Spacing.m) {
                        TintIcon(kind: item.kind, size: 64)
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text(Format.kind(item.kind))
                                .font(DS.Typography.label)
                                .foregroundStyle(DS.Tints.of(item.kind).ink)
                            Text(item.title)
                                .font(DS.Typography.title)
                                .foregroundStyle(DS.Colors.textPrimary)
                        }
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.m) {
                        if let dosage = item.dosage {
                            fact(symbol: "number", label: item.kind == .medication ? "How much" : "How many", value: dosage)
                        }
                        fact(symbol: "clock", label: "When", value: Format.schedule(item))
                        if let end = item.endDate {
                            fact(symbol: "calendar", label: "Until", value: Format.day(Format.calendarDate(end)))
                        }
                    }
                    .dsCard()

                    if let instructions = item.instructions {
                        VStack(alignment: .leading, spacing: DS.Spacing.s) {
                            SectionLabel("How to do it")
                            Text(simpler ?? instructions)
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

                        ReadAloudButton(text: readAloudText(instructions), id: "item-\(item.id)")
                        if CareAI.isAvailable && simpler == nil {
                            Button {
                                simplify(instructions)
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

                    if let task = currentTask {
                        Button {
                            Task {
                                await model.toggle(task)
                                if !task.isDone { dismiss() }
                            }
                        } label: {
                            Label(task.isDone ? "Mark as not done" : "Mark as done", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                        }
                        .buttonStyle(.dsPrimary)
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
        .onDisappear { Speaker.shared.stop() }
    }

    private func fact(symbol: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.s) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(DS.Colors.textSecondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.textSecondary)
                Text(value)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func readAloudText(_ instructions: String) -> String {
        [item.title, item.dosage, Format.schedule(item), simpler ?? instructions]
            .compactMap { $0 }
            .joined(separator: ". ")
    }

    private func simplify(_ text: String) {
        isSimplifying = true
        Task {
            simpler = await CareAI.simplify(text)
            isSimplifying = false
        }
    }
}
