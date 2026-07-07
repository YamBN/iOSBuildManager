import SwiftUI

/// Summary of the soonest-expiring signing asset, surfaced as a dashboard
/// warning for the free-Apple-ID 7-day refresh cycle.
struct SigningHealth {
    enum Level {
        case unknown   // nothing detected yet
        case ok        // plenty of time left
        case expiringSoon
        case expired
    }

    var level: Level
    var name: String?
    var expirationDate: Date?
    var daysRemaining: Int?

    /// Whether a warning banner should be shown.
    var needsAttention: Bool {
        level == .expiringSoon || level == .expired
    }

    var color: Color {
        switch level {
        case .expired: return .red
        case .expiringSoon: return .orange
        default: return .green
        }
    }

    var systemImage: String {
        level == .expired ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark.fill"
    }

    var message: String {
        switch level {
        case .expired:
            return "Signing expired — a fresh build is required before it will install on a device."
        case .expiringSoon:
            if let days = daysRemaining, days > 0 {
                return "Signing expires in \(days) day\(days == 1 ? "" : "s"). Rebuild soon to keep sideloaded apps working."
            }
            return "Signing expires today. Rebuild now to keep sideloaded apps working."
        default:
            return ""
        }
    }
}
