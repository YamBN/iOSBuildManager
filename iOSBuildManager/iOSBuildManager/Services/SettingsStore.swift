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

/// Persisted user preferences. Stored as JSON in Application Support.
struct AppSettings: Codable, Sendable, Hashable {
    var outputURL: URL = AppPaths.defaultOutputURL
    var keepLatestIPA: Bool = true
    var keepBuildHistoryCount: Int = 20
    var autoCleanOldBuilds: Bool = true
    var theme: AppTheme = .dark
    var validateICloudOutput: Bool = true
    var notifyOnBuildComplete: Bool = true
    var scheduledBuildsEnabled: Bool = false
    var scheduledBuildIntervalDays: Int = 6
    var scheduledProjectId: UUID? = nil
}

/// Observable, persisted settings. Owned by `AppModel` and injected into views.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    init() {
        self.settings = Self.load()
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
