import Core
import Foundation
import Supabase

final class SupabaseAuthRepository: AuthRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func sessionChanges() -> AsyncStream<UserSession?> {
        AsyncStream { continuation in
            let task = Task { [client] in
                for await (event, session) in client.auth.authStateChanges {
                    guard !Task.isCancelled else { break }
                    guard let session else {
                        continuation.yield(nil)
                        continue
                    }
                    switch event {
                    case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                        continuation.yield(UserSession(userID: session.user.id, email: session.user.email))
                    case .signedOut, .userDeleted:
                        continuation.yield(nil)
                    default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signIn(email: String, password: String) async throws(Core.AuthError) -> UserSession {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            return UserSession(userID: session.user.id, email: session.user.email)
        } catch {
            if error is URLError { throw .network }
            if let error = error as? Supabase.AuthError, error.errorCode == .invalidCredentials { throw .invalidCredentials }
            throw .unknown
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
    }
}
