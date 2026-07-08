import Foundation

/// Well-known filesystem locations used by the app.
enum AppPaths {
    static let bundleIdentifier = "com.yambn.iOSBuildManager"
    static let schedulerIdentifier = "com.yambn.iOSBuildManager.scheduler"

    static var supportURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("iOSBuildManager", isDirectory: true)
    }

    static var projectsURL: URL { supportURL.appendingPathComponent("projects.json") }
    static var historyURL: URL { supportURL.appendingPathComponent("builds.json") }
    static var settingsURL: URL { supportURL.appendingPathComponent("settings.json") }
    static var derivedDataURL: URL { supportURL.appendingPathComponent("DerivedData", isDirectory: true) }
    static var logsURL: URL { supportURL.appendingPathComponent("Logs", isDirectory: true) }
    static var helperScriptURL: URL { supportURL.appendingPathComponent("package-ipa.sh") }
    static var scheduledBuildScriptURL: URL { supportURL.appendingPathComponent("scheduled-build.sh") }

    static var launchAgentURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(schedulerIdentifier).plist")
    }

    /// Default iCloud Drive output folder used for SideStore / AltStore installs.
    static var defaultOutputURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/iOS Builds",
                                     isDirectory: true)
    }

    /// Ensures the Application Support tree exists.
    static func ensureDirectories() {
        let fm = FileManager.default
        for url in [supportURL, logsURL, derivedDataURL] {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func derivedData(for project: Project) -> URL {
        derivedDataURL.appendingPathComponent(project.id.uuidString, isDirectory: true)
    }
}
