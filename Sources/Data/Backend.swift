import Core
import Foundation
import Supabase

/// Backend connection settings. Only the public publishable key ships in the app.
public struct BackendConfig: Sendable {
    public let url: URL
    public let publishableKey: String

    public init(url: URL, publishableKey: String) {
        self.url = url
        self.publishableKey = publishableKey
    }
}

/// The Data layer as the app sees it: two protocols from Core, backed by Supabase.
public struct Backend: Sendable {
    public let auth: any AuthRepository
    public let care: any CareRepository

    public init(config: BackendConfig) {
        let client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: KeychainSessionStorage(service: "com.juanvizh.carehold.session"),
                    flowType: .pkce,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        auth = SupabaseAuthRepository(client: client)
        care = SupabaseCareRepository(client: client)
    }
}
