import Core
import DesignSystem
import SwiftUI

/// One conversation between a patient and a clinician. Used by both sides.
struct ChatThread: View {
    let messages: [Message]
    let myID: UUID
    let otherName: String
    let placeholder: String
    let send: (String) async -> Bool

    @State private var draft = ""
    @State private var isSending = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: DS.Spacing.s) {
                        if messages.isEmpty {
                            EmptyNote(symbol: DS.Symbols.message, text: "No messages yet. Write to \(otherName) below.")
                        }
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            if index == 0 || !Calendar.current.isDate(message.createdAt, inSameDayAs: messages[index - 1].createdAt) {
                                Text(Format.day(message.createdAt))
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.textSecondary)
                                    .padding(.top, DS.Spacing.s)
                            }
                            Bubble(message: message, isMine: message.senderID == myID, otherName: otherName)
                                .id(message.id)
                        }
                    }
                    .padding(DS.Spacing.m)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: messages.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            composer
        }
        .dsScreen()
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.s) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.ds)
                .lineLimit(1...5)
                .focused($focused)
            Button {
                let text = draft
                isSending = true
                Task {
                    if await send(text) { draft = "" }
                    isSending = false
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DS.Colors.onAccent)
                    .frame(width: DS.Size.buttonHeight, height: DS.Size.buttonHeight)
                    .background(DS.Colors.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.s)
        .background(DS.Colors.background)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Colors.hairline).frame(height: DS.Size.hairline)
        }
    }
}

private struct Bubble: View {
    let message: Message
    let isMine: Bool
    let otherName: String

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: DS.Spacing.xxl) }
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                if message.kind == .reminder {
                    Label("Reminder", systemImage: DS.Symbols.reminder)
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Tints.reminder.ink)
                }
                Text(message.body)
                    .font(DS.Typography.body)
                    .foregroundStyle(isMine ? DS.Colors.onAccent : DS.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text(Format.time(message.createdAt))
                    .font(DS.Typography.caption)
                    .foregroundStyle(isMine ? DS.Colors.onAccent.opacity(0.85) : DS.Colors.textSecondary)
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.s)
            .background(fill, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .strokeBorder(isMine || message.kind == .reminder ? .clear : DS.Colors.hairline, lineWidth: DS.Size.hairline)
            )
            if !isMine { Spacer(minLength: DS.Spacing.xxl) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isMine ? "You" : otherName)\(message.kind == .reminder ? ", reminder" : ""): \(message.body), \(Format.time(message.createdAt))")
    }

    private var fill: Color {
        if isMine { return DS.Colors.accent }
        return message.kind == .reminder ? DS.Tints.reminder.fill : DS.Colors.surface
    }
}
