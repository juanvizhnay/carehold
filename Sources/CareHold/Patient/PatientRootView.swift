import Core
import DesignSystem
import SwiftUI

/// Three tabs, each answering one question:
/// Today "what do I do now?", Visits "when do I go, and what did they tell me?",
/// Messages "how do I reach my care team?".
struct PatientRootView: View {
    @State private var model: PatientModel
    @State private var tab: Tab = .today
    @Environment(\.scenePhase) private var scenePhase
    let signOut: () async -> Void

    enum Tab: Hashable {
        case today
        case visits
        case messages
    }

    init(me: Profile, care: any CareRepository, signOut: @escaping () async -> Void) {
        _model = State(initialValue: PatientModel(me: me, care: care))
        self.signOut = signOut
    }

    var body: some View {
        Group {
            if !model.hasLoaded {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .dsScreen()
            } else if model.clinicians.isEmpty && model.errorMessage == nil {
                JoinClinicianView(model: model, signOut: signOut)
            } else {
                tabs
            }
        }
        .task { await model.load() }
        .task {
            // No push notifications in the demo: refresh quietly while the app is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await model.refreshMessages()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            NavigationStack {
                PatientTodayScreen(model: model, signOut: signOut, openMessages: { tab = .messages })
            }
            .tabItem { Label("Today", systemImage: "sun.max.fill") }
            .tag(Tab.today)

            NavigationStack {
                PatientVisitsScreen(model: model)
            }
            .tabItem { Label("Visits", systemImage: "calendar") }
            .tag(Tab.visits)

            NavigationStack {
                PatientMessagesScreen(model: model)
            }
            .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right.fill") }
            .badge(model.unreadCount)
            .tag(Tab.messages)
        }
    }
}

/// Shown once: the patient types the six-letter code their care provider gave them.
struct JoinClinicianView: View {
    let model: PatientModel
    let signOut: () async -> Void
    @State private var code = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                Wordmark(height: 48)
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.xl)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Hello, \(model.me.firstName)")
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Colors.textPrimary)
                    Text("Type the 6-letter code your doctor or care provider gave you. You only need to do this once.")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                TextField("ABC234", text: $code)
                    .textFieldStyle(.ds)
                    .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.join)
                    .onSubmit(join)
                    .onChange(of: code) { _, value in
                        code = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    }
                    .accessibilityLabel("Care code")
                if let errorMessage {
                    ErrorText(errorMessage)
                }
                Button("Connect", action: join)
                    .buttonStyle(.dsPrimary(isLoading: isLoading))
                    .disabled(code.count != 6 || isLoading)
                Button("Sign out") { Task { await signOut() } }
                    .buttonStyle(.dsSecondary)
            }
            .padding(DS.Spacing.l)
        }
        .dsScreen()
        .onAppear { focused = true }
    }

    private func join() {
        guard code.count == 6 else { return }
        focused = false
        isLoading = true
        Task {
            errorMessage = await model.join(code: code)
            isLoading = false
        }
    }
}
