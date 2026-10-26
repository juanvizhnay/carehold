import Core
import Data
import DesignSystem
import SwiftUI

/// Decides what the user sees: sign-in, or the patient or clinician app.
struct RootView: View {
    private enum Phase: Equatable {
        case loading
        case signedOut
        /// Signed in but the profile could not be loaded (offline on launch).
        case failed(UserSession)
        case patient(Profile)
        case clinician(Profile)
    }

    let backend: Backend
    @State private var phase: Phase = .loading

    var body: some View {
        content
            .preferredColorScheme(.light)
            .tint(DS.Colors.accent)
            .task {
                for await session in backend.auth.sessionChanges() {
                    await handle(session)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            VStack { Wordmark(height: 56) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .dsScreen()
        case .signedOut:
            SignInView(model: SignInModel(auth: backend.auth))
        case .failed(let session):
            VStack(spacing: DS.Spacing.l) {
                EmptyNote(symbol: "wifi.slash", text: "We couldn't load your information. Please check your internet connection.")
                Button("Try again") { Task { await handle(session, force: true) } }
                    .buttonStyle(.dsPrimary)
                Button("Sign out") { Task { await signOut() } }
                    .buttonStyle(.dsSecondary)
            }
            .padding(DS.Spacing.l)
            .frame(maxHeight: .infinity)
            .dsScreen()
        case .patient(let profile):
            PatientRootView(me: profile, care: backend.care, signOut: signOut)
                .id(profile.id)
        case .clinician(let profile):
            ClinicianRootView(me: profile, care: backend.care, signOut: signOut)
                .id(profile.id)
        }
    }

    private func handle(_ session: UserSession?, force: Bool = false) async {
        guard let session else {
            await CareReminders.removeAll()
            phase = .signedOut
            return
        }
        switch phase {
        case .patient(let profile) where profile.id == session.userID && !force: return
        case .clinician(let profile) where profile.id == session.userID && !force: return
        default: break
        }
        do {
            let profile = try await backend.care.myProfile()
            phase = profile.role == .clinician ? .clinician(profile) : .patient(profile)
        } catch {
            phase = .failed(session)
        }
    }

    private func signOut() async {
        Speaker.shared.stop()
        await CareReminders.removeAll()
        await backend.auth.signOut()
        phase = .signedOut
    }
}
