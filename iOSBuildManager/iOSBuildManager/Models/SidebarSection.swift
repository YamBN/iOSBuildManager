import Foundation
import SwiftUI

/// Top-level sidebar destinations.
enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, builds, profiles, certificates, devices, settings, logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .builds: return "Builds"
        case .profiles: return "Profiles"
        case .certificates: return "Certificates"
        case .devices: return "Devices"
        case .settings: return "Settings"
        case .logs: return "Logs"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "cube"
        case .builds: return "shippingbox"
        case .profiles: return "doc.badge.gearshape"
        case .certificates: return "checkmark.seal"
        case .devices: return "iphone"
        case .settings: return "gearshape"
        case .logs: return "scroll"
        }
    }
}
