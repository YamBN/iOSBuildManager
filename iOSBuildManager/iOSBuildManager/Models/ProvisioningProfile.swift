import Foundation

/// A provisioning profile installed under `~/Library/MobileDevice/Provisioning Profiles`.
struct ProvisioningProfile: Codable, Identifiable, Hashable, Sendable {
    var id: String { uuid }
    var name: String
    var uuid: String
    var teamName: String
    var teamId: String
    var expirationDate: Date?
    var kind: Kind
    var fileURL: URL

    enum Kind: String, Codable, Sendable {
        case development = "Development"
        case adHoc = "Ad Hoc"
        case appStore = "App Store"
        case enterprise = "Enterprise"

        var systemImage: String {
            switch self {
            case .development: return "hammer.circle"
            case .adHoc: return "iphone.circle"
            case .appStore: return "shippingbox.circle"
            case .enterprise: return "building.2.crop.circle"
            }
        }
    }

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate < .now
    }

    var expiresSoon: Bool {
        guard let expirationDate, !isExpired else { return false }
        return expirationDate.timeIntervalSinceNow < 14 * 24 * 3600
    }

    var statusLabel: String {
        if isExpired { return "Expired" }
        if expiresSoon { return "Expiring Soon" }
        return "Valid"
    }
}
