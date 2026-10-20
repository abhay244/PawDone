import Foundation

/// Values set at build time in Config/Secrets.xcconfig and passed through Info.plist.
enum AppConfig {
    static var supabaseURL: URL? {
        value(for: "SUPABASE_HOST").flatMap { URL(string: "https://\($0)") }
    }

    static var supabaseAnonKey: String? {
        value(for: "SUPABASE_ANON_KEY")
    }

    /// RevenueCat public SDK key.
    /// - Xcode (debug) builds: `REVENUECAT_API_KEY`, usually the Test Store key (`test_…`).
    /// - TestFlight and App Store (release) builds: `REVENUECAT_APP_STORE_KEY` (`appl_…`).
    static var revenueCatAPIKey: String? {
        #if DEBUG
        return value(for: "REVENUECAT_API_KEY")
        #else
        let key = value(for: "REVENUECAT_APP_STORE_KEY") ?? value(for: "REVENUECAT_API_KEY")
        // Never let a Test Store key reach TestFlight or the App Store.
        guard let key, !key.hasPrefix("test_") else { return nil }
        return key
        #endif
    }

    /// Apple's standard licence agreement, used as PawDone's terms of use.
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Published from site/ by .github/workflows/pages.yml.
    static let privacyPolicyURL = URL(string: "https://abhay244.github.io/PawDone/privacy/")!
    static let supportURL = URL(string: "https://abhay244.github.io/PawDone/support/")!
    static let supportEmail = "abhayiitr5001@gmail.com"

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
