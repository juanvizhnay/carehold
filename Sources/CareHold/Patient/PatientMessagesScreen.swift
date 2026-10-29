import Core
import DesignSystem
import SwiftUI

struct PatientMessagesScreen: View {
    let model: PatientModel

    var body: some View {
        ChatThread(
            messages: model.messages,
            myID: model.me.id,
            otherName: model.clinician?.displayName ?? "your care team",
            placeholder: "Write to \(model.clinician?.displayName ?? "your care team")",
            send: { await model.send($0) }
        )
        .navigationTitle(model.clinician?.displayName ?? "Messages")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.messages.count) { await model.markThreadRead() }
    }
}

struct PatientSettingsSheet: View {
    let model: PatientModel
    let signOut: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(model.me.fullName)
                            .font(DS.Typography.title)
                            .foregroundStyle(DS.Colors.textPrimary)
                    }
                    if let clinician = model.clinician {
                        VStack(alignment: .leading, spacing: DS.Spacing.s) {
                            SectionLabel("Your care team")
                            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                                Text(clinician.displayName)
                                    .font(DS.Typography.rowTitle)
                                    .foregroundStyle(DS.Colors.textPrimary)
                                if let clinic = clinician.clinicName {
                                    Text(clinic)
                                        .font(DS.Typography.secondary)
                                        .foregroundStyle(DS.Colors.textSecondary)
                                }
                            }
                            .dsCard()
                            if let phone = clinician.phone, let url = URL(string: "tel://\(phone.filter(\.isNumber))") {
                                Button {
                                    openURL(url)
                                } label: {
                                    Label("Call \(phone)", systemImage: "phone.fill")
                                }
                                .buttonStyle(.dsSecondary)
                            }
                        }
                    }
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
                        .font(DS.Typography.label)
                }
            }
        }
    }
}
