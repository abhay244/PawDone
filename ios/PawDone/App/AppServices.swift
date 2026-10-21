import Foundation
import Supabase

/// The app's long-lived services, all sharing one Supabase client.
struct AppServices {
    let session: SessionStore
    /// Nil until Config/Secrets.xcconfig is filled in.
    let petBackend: (any PetBackend)?
    /// Nil until a RevenueCat key is set in Config/Secrets.xcconfig.
    let subscriptions: (any SubscriptionService)?
    /// The current time. Only the demo changes it (see DemoServices).
    var now: () -> Date = { .now }

    static func live() -> AppServices {
        #if DEBUG
        if isDemo { return demo().connectingPush() }
        #endif

        var client: SupabaseClient?
        if let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey {
            client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: key,
                options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
            )
        }
        return AppServices(
            session: SessionStore(
                backend: client.map { SupabaseSessionBackend(client: $0) },
                deviceID: DeviceIdentity().id()
            ),
            petBackend: client.map { SupabasePetBackend(client: $0) },
            subscriptions: AppConfig.revenueCatAPIKey.map { RevenueCatSubscriptionService(apiKey: $0) }
        ).connectingPush()
    }

    /// Sends this phone's push token to the server whenever iOS hands out a new one.
    private func connectingPush() -> AppServices {
        PushRegistrar.shared.onToken = { [weak session] token in
            Task { await session?.updatePushToken(token) }
        }
        return self
    }
}
