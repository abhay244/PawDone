import CryptoKit
import Foundation
import Security

/// One-time value for Sign in with Apple. Apple receives the hash; Supabase receives
/// the raw value and checks it against the hash inside Apple's ID token.
struct AppleSignInNonce {
    let raw: String

    var hashed: String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Couldn't generate a secure random nonce")
        raw = bytes.map { String(format: "%02x", $0) }.joined()
    }
}
