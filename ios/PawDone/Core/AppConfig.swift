import Foundation

/// Values set at build time in Config/Secrets.xcconfig and passed through Info.plist.
enum AppConfig {
    static var supabaseURL: URL? {
        value(for: "SUPABASE_HOST").flatMap { URL(string: "https://\($0)") }
    }

    static var supabaseAnonKey: String? {
        value(for: "SUPABASE_ANON_KEY")
    }

    private static func value(for key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
