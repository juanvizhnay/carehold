import Foundation

public struct UserSession: Hashable, Sendable {
    public let userID: UUID
    public let email: String?

    public init(userID: UUID, email: String?) {
        self.userID = userID
        self.email = email
    }
}

public enum AuthError: Error, Equatable, Sendable {
    case invalidCredentials
    case network
    case unknown
}

/// Sign-in lives behind this protocol so the demo's email + password can later become
/// email codes (like Tosaki) or Sign in with Apple without touching the screens' logic.
public protocol AuthRepository: Sendable {
    func sessionChanges() -> AsyncStream<UserSession?>
    func signIn(email: String, password: String) async throws(AuthError) -> UserSession
    func signOut() async
}

public enum CareError: Error, Equatable, Sendable {
    case codeNotFound
    case notAllowed
    case network
    case unknown
}

/// Everything a signed-in user can read or write. Row level security on the server decides
/// what each call actually returns: a patient only gets their rows, a clinician only their patients'.
public protocol CareRepository: Sendable {
    func myProfile() async throws(CareError) -> Profile
    func updateMyProfile(fullName: String, phone: String?) async throws(CareError)
    /// The other side of every care link: a patient's clinicians or a clinician's patients.
    func contacts() async throws(CareError) -> [Profile]
    func joinClinician(code: String) async throws(CareError) -> UUID

    func appointments() async throws(CareError) -> [Appointment]
    func save(_ appointment: Appointment) async throws(CareError)
    func deleteAppointment(id: UUID) async throws(CareError)

    func planItems() async throws(CareError) -> [PlanItem]
    func save(_ item: PlanItem) async throws(CareError)

    func planLogs(from: CalendarDate, to: CalendarDate) async throws(CareError) -> [PlanLog]
    func save(_ log: PlanLog) async throws(CareError)
    func deleteLog(id: UUID) async throws(CareError)

    func messages() async throws(CareError) -> [Message]
    func send(_ message: Message) async throws(CareError)
    func markRead(messageIDs: [UUID]) async throws(CareError)
}
