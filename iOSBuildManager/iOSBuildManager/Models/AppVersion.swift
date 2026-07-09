import Foundation

/// Source of truth for the app's version, changelog, and credits.
///
/// Mirrors the project-level versioning rule: every release bumps the version
/// (semver) and prepends a changelog entry. The About screen shows the full
/// feature list and the latest changelog entries.
enum AppVersion {
    static let version: String = "1.3.0"
    static let buildNumber: String = "4"

    // MARK: - Credits

    static let authorName = "Yam.B"
    static let authorGitHubHandle = "YamBN"
    static let authorGitHubURL = URL(string: "https://github.com/YamBN")!
    static let repositoryURL = URL(string: "https://github.com/YamBN/iOSBuildManager")!

    // MARK: - What's in this version

    /// The complete capability list shown in About.
    static let highlights: [String] = [
        "One-click builds of any .xcodeproj / .xcworkspace with live log streaming",
        "Automatic IPA packaging (Payload → zip) with versioned names + latest.ipa",
        "iCloud Drive output for SideStore / AltStore / Sideloadly installs",
        "Provisioning profile manager with team and expiry status",
        "Signing certificate manager backed by the keychain",
        "Signing-expiry warning banner for the free-Apple-ID 7-day cycle",
        "Accurate device detection via devicectl — only reachable devices are install targets",
        "Install on device with one click (devicectl)",
        "Flexible scheduled builds — every N days, daily, or weekly on chosen days at a set time",
        "Runs in the menu bar; closing the window keeps it working in the background",
        "macOS notifications on build success and failure",
        "Code-signature check before packaging",
        "Xcode Run Script helper — package after every Xcode build, no build loops",
        "Menu bar panel with build actions, live build progress, a device-picker submenu, recent builds, and project switcher",
        "Checks GitHub for new releases on launch (optional, no telemetry)",
        "Dark / Light / System themes; local-only, no analytics",
    ]

    // MARK: - Changelog

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

    /// Newest entry first.
    static let changelog: [ChangelogEntry] = [
        .init(version: "1.3.0", date: "2026-07-09", type: .minor,
              summary: "Menu bar panel now shows live build progress with percentage and elapsed time, and Install on Device is a proper device-picker submenu instead of silently installing to the first device."),
        .init(version: "1.2.0", date: "2026-07-09", type: .minor,
              summary: "Checks GitHub for new releases on launch and offers a one-click download; fixed the sidebar rendering flat gray instead of matching the app's navy glass background."),
        .init(version: "1.1.0", date: "2026-07-08", type: .minor,
              summary: "Flexible scheduling (every N days, daily, or weekly on chosen days at a set time), and the app now keeps running in the menu bar when you close its window."),
        .init(version: "1.0.0", date: "2026-07-08", type: .major,
              summary: "First public release: build, package, and ship IPAs for the free-Apple-ID sideloading workflow — with signing management, scheduled rebuilds, device installs, notifications, and a menu bar panel."),
    ]
}
