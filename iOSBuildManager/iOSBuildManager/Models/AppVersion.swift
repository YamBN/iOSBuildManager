import Foundation

/// Source of truth for the app's version and human-readable changelog.
///
/// Mirrors the project-level versioning rule: every change bumps the version
/// (semver) and prepends a changelog entry. The UI shows the latest entries
/// via the About / Settings screens.
enum AppVersion {
    static let version: String = "1.0.0"
    static let buildNumber: String = "1"

    enum ChangeType: String, Codable, Sendable, CaseIterable {
        case patch, minor, major

        var displayName: String {
            switch self {
            case .patch: return "Patch"
            case .minor: return "Minor"
            case .major: return "Major"
            }
        }

        var systemImage: String {
            switch self {
            case .patch: return "wrench.and.screwdriver"
            case .minor: return "sparkles"
            case .major: return "rocket"
            }
        }
    }

    struct ChangelogEntry: Identifiable, Hashable, Sendable {
        let id = UUID()
        let version: String
        let date: String
        let type: ChangeType
        let summary: String
    }

    /// Newest entry first. The UI displays only the latest 3.
    static let changelog: [ChangelogEntry] = [
        .init(version: "1.0.0", date: "2026-07-07", type: .major,
              summary: "השקה ראשונית: בנייה, אריזת IPA, היסטוריית בניות ותזמון LaunchAgent")
    ]
}
