import Foundation
import SwiftUI

enum AppTheme: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// How scheduled builds recur.
enum ScheduleFrequency: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case everyNDays   // launchd StartInterval (roughly every N days from load)
    case daily        // launchd StartCalendarInterval at a fixed time
    case weekly       // launchd StartCalendarInterval on chosen weekdays at a time

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .everyNDays: return "Every N Days"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }
}

/// Weekday helpers using launchd's convention: 0 = Sunday … 6 = Saturday.
enum Weekday {
    static let all = Array(0...6)
    static func shortName(_ index: Int) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][((index % 7) + 7) % 7]
    }
    static func initial(_ index: Int) -> String {
        ["S", "M", "T", "W", "T", "F", "S"][((index % 7) + 7) % 7]
    }
}

/// Persisted user preferences. Stored as JSON in Application Support.
struct AppSettings: Codable, Sendable, Hashable {
    var outputURL: URL = AppPaths.defaultOutputURL
    var keepLatestIPA: Bool = true
    var keepBuildHistoryCount: Int = 20
    var autoCleanOldBuilds: Bool = true
    var theme: AppTheme = .dark
    var validateICloudOutput: Bool = true
    var notifyOnBuildComplete: Bool = true
    var showMenuBarIcon: Bool = true
    var scheduledBuildsEnabled: Bool = false
    var scheduledBuildIntervalDays: Int = 6
    var scheduledProjectId: UUID? = nil
    var scheduleFrequency: ScheduleFrequency = .everyNDays
    var scheduleHour: Int = 3            // 0–23, used by daily/weekly
    var scheduleMinute: Int = 0          // 0–59
    var scheduleWeekdays: [Int] = [1, 4] // Mon, Thu (launchd 0=Sun…6=Sat)
    var checkForUpdatesAutomatically: Bool = true
    var skippedUpdateVersion: String? = nil // user tapped "Skip This Version"
    /// OAuth App client ID used for GitHub's device flow. Public by design —
    /// device flow needs no client secret — but each install registers its own.
    var githubClientID: String = ""

    init() {}

    /// Tolerant decoding: fields added in newer versions fall back to their
    /// defaults instead of failing the whole file and silently resetting
    /// every user setting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        outputURL = try c.decodeIfPresent(URL.self, forKey: .outputURL) ?? defaults.outputURL
        keepLatestIPA = try c.decodeIfPresent(Bool.self, forKey: .keepLatestIPA) ?? defaults.keepLatestIPA
        keepBuildHistoryCount = try c.decodeIfPresent(Int.self, forKey: .keepBuildHistoryCount) ?? defaults.keepBuildHistoryCount
        autoCleanOldBuilds = try c.decodeIfPresent(Bool.self, forKey: .autoCleanOldBuilds) ?? defaults.autoCleanOldBuilds
        theme = try c.decodeIfPresent(AppTheme.self, forKey: .theme) ?? defaults.theme
        validateICloudOutput = try c.decodeIfPresent(Bool.self, forKey: .validateICloudOutput) ?? defaults.validateICloudOutput
        notifyOnBuildComplete = try c.decodeIfPresent(Bool.self, forKey: .notifyOnBuildComplete) ?? defaults.notifyOnBuildComplete
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? defaults.showMenuBarIcon
        scheduledBuildsEnabled = try c.decodeIfPresent(Bool.self, forKey: .scheduledBuildsEnabled) ?? defaults.scheduledBuildsEnabled
        scheduledBuildIntervalDays = try c.decodeIfPresent(Int.self, forKey: .scheduledBuildIntervalDays) ?? defaults.scheduledBuildIntervalDays
        scheduledProjectId = try c.decodeIfPresent(UUID.self, forKey: .scheduledProjectId) ?? defaults.scheduledProjectId
        scheduleFrequency = try c.decodeIfPresent(ScheduleFrequency.self, forKey: .scheduleFrequency) ?? defaults.scheduleFrequency
        scheduleHour = try c.decodeIfPresent(Int.self, forKey: .scheduleHour) ?? defaults.scheduleHour
        scheduleMinute = try c.decodeIfPresent(Int.self, forKey: .scheduleMinute) ?? defaults.scheduleMinute
        scheduleWeekdays = try c.decodeIfPresent([Int].self, forKey: .scheduleWeekdays) ?? defaults.scheduleWeekdays
        checkForUpdatesAutomatically = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdatesAutomatically) ?? defaults.checkForUpdatesAutomatically
        skippedUpdateVersion = try c.decodeIfPresent(String.self, forKey: .skippedUpdateVersion) ?? defaults.skippedUpdateVersion
        githubClientID = try c.decodeIfPresent(String.self, forKey: .githubClientID) ?? defaults.githubClientID
    }
}

/// Observable, persisted settings. Owned by `AppModel` and injected into views.
@MainActor
final class SettingsStore: ObservableObject {
    private var storage: AppSettings

    /// No-op writes must neither publish nor save: SwiftUI's MenuBarExtra
    /// rewrites its `isInserted` binding during every scene update, and
    /// publishing on an equal value re-triggers the scene update — an
    /// infinite loop that pegs the CPU and hammers the disk.
    var settings: AppSettings {
        get { storage }
        set {
            guard newValue != storage else { return }
            objectWillChange.send()
            storage = newValue
            save()
        }
    }

    init() {
        self.storage = Self.load()
    }

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: AppPaths.settingsURL),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: AppPaths.settingsURL, options: .atomic)
    }

    /// Validates that the output folder is reachable and (optionally) that it is
    /// inside iCloud Drive. Returns a user-facing message when something is off.
    func validateOutput() -> String? {
        let fm = FileManager.default
        let url = settings.outputURL
        if !url.path.contains("Mobile Documents/com~apple~CloudDocs") {
            return settings.validateICloudOutput ? "Output folder is not inside iCloud Drive." : nil
        }
        if !fm.fileExists(atPath: url.path) {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                return "Could not create iCloud output folder: \(error.localizedDescription)"
            }
        }
        return nil
    }
}
