import Foundation

/// Source of truth for the app's version, changelog, and credits.
///
/// Mirrors the project-level versioning rule: every release bumps the version
/// (semver) and prepends a changelog entry. The About screen shows the full
/// feature list and the latest changelog entries.
enum AppVersion {
    static let version: String = "1.6.0"
    static let buildNumber: String = "9"

    // MARK: - Credits

    static let authorName = "Yam.B"
    static let authorGitHubHandle = "YamBN"
    static let authorGitHubURL = URL(string: "https://github.com/YamBN")!
    static let repositoryURL = URL(string: "https://github.com/YamBN/iOSBuildManager")!

    // MARK: - What's in this version

    /// The complete capability list shown in About.
    static let highlights: [String] = [
        "One-click builds of any .xcodeproj / .xcworkspace / Swift package with live log streaming",
        "Builds macOS apps too — export as a .dmg or zipped .app, platform auto-detected from the scheme",
        "Shows the icon of the app you're building, pulled from its latest build",
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
        "Appearance — give the app you're building its own icon and name, written into the bundle on the next build",
        "GitHub built in: sign in, commit and push, publish repositories, watch Actions, cut releases",
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
        .init(version: "1.6.0", date: "2026-07-26", type: .minor,
              summary: "Appearance is now its own section and belongs to the project, not to this app: the icon and name you set there are written into the .app on the next build, so the app you install really carries them. Removed the duplicate app-logo/app-name controls and the second theme picker, and dropped the redundant app title above the sidebar."),
        .init(version: "1.5.1", date: "2026-07-26", type: .patch,
              summary: "Ships the 1.5.0 features as a downloadable build — 1.5.0 itself failed to compile on the release runner because of a strict-concurrency error in the logo drop handler."),
        .init(version: "1.5.0", date: "2026-07-26", type: .minor,
              summary: "New Appearance tab for making the app yours: a custom logo (scaled correctly for the Dock, menu bar, and sidebar), a custom app name, theme, and per-project icons and display names. New GitHub section: sign in through the browser or the GitHub CLI, commit and push, publish a repository, watch Actions, and cut a release with your build attached. Also fixes macOS builds failing to read Info.plist."),
        .init(version: "1.4.0", date: "2026-07-12", type: .minor,
              summary: "Build macOS apps and Swift packages, not just iOS: platform is auto-detected from the scheme, packages build with swift build and are wrapped into an app, and you can export a .dmg or zipped .app. The project's real app icon now appears in the panel and dashboard, and the progress bar shows a percentage from the very first build."),
        .init(version: "1.3.1", date: "2026-07-09", type: .patch,
              summary: "The menu bar's Install on Device row now lines up with its neighbours and opens a device-picker flyout to the right on hover — no click, no misaligned badge."),
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
