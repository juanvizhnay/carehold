import Core
import DesignSystem
import SwiftUI

struct ClinicianPatientsScreen: View {
    let model: ClinicianModel
    @State private var search = ""

    private var filtered: [Profile] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let list = query.isEmpty ? model.patients : model.patients.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
        // Patients who wrote first, then by name.
        return list.sorted { lhs, rhs in
            let l = model.unreadCount(from: lhs.id)
            let r = model.unreadCount(from: rhs.id)
            if (l > 0) != (r > 0) { return l > 0 }
            return lhs.fullName.localizedStandardCompare(rhs.fullName) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                if model.patients.isEmpty {
                    EmptyNote(symbol: "person.2", text: "No patients yet. Share your code so they can connect.")
                    PatientCodeCard(code: model.me.clinicianCode)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, patient in
                            if index > 0 {
                                Divider().overlay(DS.Colors.hairline).padding(.leading, 76)
                            }
                            NavigationLink(value: patient.id) {
                                PatientRow(model: model, patient: patient)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .dsCard(padding: 0)
                    PatientCodeCard(code: model.me.clinicianCode)
                }
            }
            .padding(DS.Spacing.m)
        }
        .dsScreen()
        .navigationTitle("Patients")
        .searchable(text: $search, prompt: "Search patients")
        .refreshable { await model.load() }
        .navigationDestination(for: UUID.self) { patientID in
            ClinicianPatientScreen(model: model, patientID: patientID)
        }
    }
}

private struct PatientRow: View {
    let model: ClinicianModel
    let patient: Profile

    var body: some View {
        let unread = model.unreadCount(from: patient.id)
        HStack(spacing: DS.Spacing.s) {
            Initials(name: patient.displayName)
            VStack(alignment: .leading, spacing: 2) {
                Text(patient.displayName)
                    .font(DS.Typography.rowTitle)
                    .foregroundStyle(DS.Colors.textPrimary)
                Text(subtitle)
                    .font(DS.Typography.secondary)
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            Spacer(minLength: 0)
            if unread > 0 {
                Text("\(unread)")
                    .font(DS.Typography.caption.weight(.bold))
                    .foregroundStyle(DS.Colors.onAccent)
                    .padding(.horizontal, DS.Spacing.xs)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(DS.Colors.accent, in: Capsule())
                    .accessibilityLabel("\(unread) new messages")
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(DS.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(DS.Spacing.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let next = model.nextVisit(of: patient.id) {
            parts.append("Next: \(Format.day(next.startsAt))")
        }
        if let adherence = model.weeklyAdherence(of: patient.id) {
            parts.append("\(Int((adherence * 100).rounded()))% done this week")
        }
        return parts.isEmpty ? "No plan yet" : parts.joined(separator: " · ")
    }
}

struct Initials: View {
    let name: String

    var body: some View {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        Text(letters.isEmpty ? "?" : letters)
            .font(DS.Typography.label)
            .foregroundStyle(DS.Tints.visit.ink)
            .frame(width: DS.Size.icon, height: DS.Size.icon)
            .background(DS.Tints.visit.fill, in: Circle())
            .accessibilityHidden(true)
    }
}
