import Foundation

/// A code-signing identity (certificate + private key pair) available in the keychain.
struct SigningIdentity: Codable, Identifiable, Hashable, Sendable {
    var id: String { hash }
    var hash: String
    var name: String
    var expirationDate: Date?

    /// Team ID parsed out of the trailing parenthesized token in the common name,
    /// e.g. "Apple Development: Jane Doe (ABCDE12345)" -> "ABCDE12345".
    var teamId: String? {
        guard let open = name.lastIndex(of: "("), let close = name.lastIndex(of: ")"), open < close else { return nil }
        return String(name[name.index(after: open)..<close])
    }

    var kind: Kind {
        if name.hasPrefix("Apple Distribution") || name.hasPrefix("iPhone Distribution") { return .distribution }
        if name.hasPrefix("Apple Development") || name.hasPrefix("iPhone Developer") { return .development }
        return .other
    }

    enum Kind: String, Sendable {
        case development = "Development"
        case distribution = "Distribution"
        case other = "Other"

        var systemImage: String {
            switch self {
            case .development: return "hammer.circle"
            case .distribution: return "shippingbox.circle"
            case .other: return "person.badge.key"
            }
        }
    }

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate < .now
    }

    var expiresSoon: Bool {
        guard let expirationDate, !isExpired else { return false }
        return expirationDate.timeIntervalSinceNow < 30 * 24 * 3600
    }

    var statusLabel: String {
        if isExpired { return "Expired" }
        if expiresSoon { return "Expiring Soon" }
        return "Valid"
    }
}
