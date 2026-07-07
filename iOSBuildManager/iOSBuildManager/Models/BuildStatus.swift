import Foundation

/// Lifecycle state of a single build job.
enum BuildStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case idle
    case building
    case success
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .building: return "Building"
        case .success: return "Success"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "circle.dotted"
        case .building: return "gearshape.2"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "stop.circle"
        }
    }
}
