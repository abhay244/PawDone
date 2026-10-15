import Foundation

/// Values set at build time in Config/Secrets.xcconfig and passed through Info.plist.
enum AppConfig {
    static var supabaseURL: URL? {
        value(for: "SUPABASE_HOST").flatMap { URL(string: "https://\($0)") }
    }

    static var supabaseAnonKey: String? {
        value(for: "SUPABASE_ANON_KEY")
    }

    /// RevenueCat public SDK key: `appl_…` for the App Store, `test_…` for RevenueCat's Test Store.
    static var revenueCatAPIKey: String? {
        guard let key = value(for: "REVENUECAT_API_KEY") else { return nil }
        #if !DEBUG
        // Never let a Test Store key reach TestFlight or the App Store.
        if key.hasPrefix("test_") { return nil }
        #endif
        return key
    }

    /// Shown on the paywall. Apple's standard licence agreement, unless PawDone gets its own.
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Shown on the paywall. Apple requires one before submission; set it once the website exists.
    static let privacyPolicyURL: URL? = nil

    /// Google sign-in is offered only once its client IDs are set.
    static var isGoogleSignInConfigured: Bool {
        value(for: "GIDClientID") != nil && value(for: "GIDServerClientID") != nil
    }

    private static func value(for key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
