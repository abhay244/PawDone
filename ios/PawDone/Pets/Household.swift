import Foundation

/// An open invite to the user's household.
nonisolated struct Invite: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let code: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case code = "token"
        case expiresAt = "expires_at"
    }

    init(id: UUID, code: String, expiresAt: Date) {
        self.id = id
        self.code = code
        self.expiresAt = expiresAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        expiresAt = try container.decodeServerDate(forKey: .expiresAt)
    }
}

/// What an invite code is for, shown before joining.
nonisolated struct InvitePreview: Decodable, Equatable, Sendable {
    let ownerName: String
    let petName: String?
    let petSpecies: PetSpecies?

    enum CodingKeys: String, CodingKey {
        case ownerName = "owner_name"
        case petName = "pet_name"
        case petSpecies = "pet_species"
    }
}

/// A household the user helps in. Inactive while the owner has no Premium.
nonisolated struct Membership: Decodable, Identifiable, Equatable, Sendable {
    let ownerID: UUID
    let ownerName: String
    let petID: UUID?
    let petName: String?
    let active: Bool

    var id: UUID { ownerID }

    enum CodingKeys: String, CodingKey {
        case active
        case ownerID = "owner_id"
        case ownerName = "owner_name"
        case petID = "pet_id"
        case petName = "pet_name"
    }
}

nonisolated enum InviteCode {
    /// As typed by people: upper case, letters and digits only.
    static func normalize(_ input: String) -> String {
        String(input.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    /// Split in two for reading aloud, e.g. "K7P2 QX9M".
    static func display(_ code: String) -> String {
        let normalized = normalize(code)
        guard normalized.count == 8 else { return normalized }
        return "\(normalized.prefix(4)) \(normalized.suffix(4))"
    }
}
