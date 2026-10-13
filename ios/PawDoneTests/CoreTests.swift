import CryptoKit
import Foundation
import Testing
@testable import PawDone

struct AppleSignInNonceTests {
    @Test func hashIsSHA256OfRawValue() {
        let nonce = AppleSignInNonce()
        let expected = SHA256.hash(data: Data(nonce.raw.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(nonce.hashed == expected)
    }

    @Test func eachNonceIsUnique() {
        #expect(AppleSignInNonce().raw != AppleSignInNonce().raw)
        #expect(AppleSignInNonce().raw.count == 64)
    }
}

struct DeviceIdentityTests {
    @Test func idIsStableAcrossInstances() {
        let identity = DeviceIdentity(service: "com.abhaysingh.pawdone.tests.\(UUID().uuidString)")
        defer { identity.reset() }

        let first = identity.id()
        #expect(DeviceIdentity(service: identity.service).id() == first)
        #expect((8...64).contains(first.count))
    }
}
