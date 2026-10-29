import Core
import DesignSystem
import Observation
import SwiftUI

@Observable @MainActor
final class SignInModel {
    var email = ""
    var password = ""
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let auth: any AuthRepository

    init(auth: any AuthRepository) {
        self.auth = auth
    }

    var canSubmit: Bool {
        email.contains("@") && !password.isEmpty && !isLoading
    }

    func submit() async {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // RootView reacts to the session change; nothing else to do here.
            _ = try await auth.signIn(email: email, password: password)
        } catch {
            errorMessage = switch error {
            case .invalidCredentials: "That email or password doesn't match. Please try again."
            case .network: "You seem to be offline. Please check your connection."
            case .unknown: "Something went wrong. Please try again."
            }
        }
    }
}

struct SignInView: View {
    @Bindable var model: SignInModel
    @FocusState private var field: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                Wordmark(height: 64)
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.xxl)
                    .padding(.bottom, DS.Spacing.s)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Welcome")
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Colors.textPrimary)
                    Text("Your visits, medicines and exercises, all in one place.")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    Text("Email")
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Colors.textPrimary)
                    TextField("Email", text: $model.email, prompt: dsPrompt("Type your email"))
                        .textFieldStyle(.ds)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($field, equals: .email)
                        .onSubmit { field = .password }

                    Text("Password")
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Colors.textPrimary)
                        .padding(.top, DS.Spacing.xs)
                    SecureField("Password", text: $model.password, prompt: dsPrompt("Type your password"))
                        .textFieldStyle(.ds)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($field, equals: .password)
                        .onSubmit { submit() }
                }

                if let message = model.errorMessage {
                    ErrorText(message)
                }

                Button("Sign in", action: submit)
                    .buttonStyle(.dsPrimary(isLoading: model.isLoading))
                    .disabled(!model.canSubmit)
            }
            .padding(DS.Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .dsScreen()
        .onAppear { field = .email }
        .onChange(of: model.errorMessage) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
    }

    private func submit() {
        field = nil
        Task { await model.submit() }
    }
}
