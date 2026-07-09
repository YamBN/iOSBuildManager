import Foundation

/// Manages a LaunchAgent for optional scheduled builds (default: every 6 days).
enum SchedulerService {
    /// Identifiers used by older builds of this app; cleaned up on launch so a
    /// bundle-id rename doesn't leave orphaned agents running.
    private static let legacyIdentifiers = [
        "com.rontop.iOSBuildManager.scheduler",
        "com.yambenbaruch.iOSBuildManager.scheduler",
    ]

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: AppPaths.launchAgentURL.path)
    }

    /// Unloads and deletes LaunchAgents installed under old identifiers.
    /// Returns true when one was found, so the caller can re-install under
    /// the current identifier.
    @discardableResult
    static func removeLegacyAgents() async -> Bool {
        let fm = FileManager.default
        var foundAny = false
        for identifier in legacyIdentifiers {
            let url = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/\(identifier).plist")
            guard fm.fileExists(atPath: url.path) else { continue }
            foundAny = true
            _ = try? await ShellRunner.collect(
                command: "/bin/launchctl",
                arguments: ["unload", "-w", url.path]
            )
            try? fm.removeItem(at: url)
        }
        return foundAny
    }

    /// Installs the helper script, generates the scheduled build script, writes
    /// the LaunchAgent plist, and loads it with `launchctl`.
    static func enable(project: Project, settings: AppSettings) async throws {
        AppPaths.ensureDirectories()
        try ScriptGenerator.installHelperScript()

        let script = ScriptGenerator.generateScheduledBuildScript(for: project)
        try script.write(to: AppPaths.scheduledBuildScriptURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: AppPaths.scheduledBuildScriptURL.path)

        // Unload any existing agent before rewriting it.
        try? await disable()

        var plist: [String: Any] = [
            "Label": AppPaths.schedulerIdentifier,
            "ProgramArguments": ["/bin/sh", AppPaths.scheduledBuildScriptURL.path],
            "RunAtLoad": false,
            "StandardOutPath": AppPaths.logsURL.appendingPathComponent("scheduler.log").path,
            "StandardErrorPath": AppPaths.logsURL.appendingPathComponent("scheduler.err").path
        ]
        for (key, value) in schedulingKeys(for: settings) { plist[key] = value }

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: AppPaths.launchAgentURL, options: .atomic)

        _ = try await ShellRunner.collect(
            command: "/bin/launchctl",
            arguments: ["load", "-w", AppPaths.launchAgentURL.path]
        )
    }

    /// Builds the launchd trigger keys for the chosen frequency.
    ///
    /// - `everyNDays` → `StartInterval` (~every N days from load).
    /// - `daily`      → `StartCalendarInterval` at Hour:Minute every day.
    /// - `weekly`     → `StartCalendarInterval`, one entry per chosen weekday
    ///   at Hour:Minute (launchd Weekday: 0 = Sunday … 6 = Saturday).
    static func schedulingKeys(for settings: AppSettings) -> [String: Any] {
        let hour = min(max(settings.scheduleHour, 0), 23)
        let minute = min(max(settings.scheduleMinute, 0), 59)

        switch settings.scheduleFrequency {
        case .everyNDays:
            return ["StartInterval": max(settings.scheduledBuildIntervalDays, 1) * 86_400]
        case .daily:
            return ["StartCalendarInterval": ["Hour": hour, "Minute": minute]]
        case .weekly:
            let days = settings.scheduleWeekdays.isEmpty ? [1] : settings.scheduleWeekdays
            let entries = days.sorted().map { day -> [String: Int] in
                ["Weekday": min(max(day, 0), 6), "Hour": hour, "Minute": minute]
            }
            return ["StartCalendarInterval": entries]
        }
    }

    /// A short human summary of the current schedule, for the UI.
    static func summary(for settings: AppSettings) -> String {
        let time = String(format: "%02d:%02d", settings.scheduleHour, settings.scheduleMinute)
        switch settings.scheduleFrequency {
        case .everyNDays:
            let n = max(settings.scheduledBuildIntervalDays, 1)
            return "Every \(n) day\(n == 1 ? "" : "s")"
        case .daily:
            return "Every day at \(time)"
        case .weekly:
            let days = settings.scheduleWeekdays.isEmpty
                ? "no days selected"
                : settings.scheduleWeekdays.sorted().map { Weekday.shortName($0) }.joined(separator: ", ")
            return "\(days) at \(time)"
        }
    }

    /// Unloads and removes the LaunchAgent.
    static func disable() async throws {
        guard FileManager.default.fileExists(atPath: AppPaths.launchAgentURL.path) else { return }
        _ = try? await ShellRunner.collect(
            command: "/bin/launchctl",
            arguments: ["unload", "-w", AppPaths.launchAgentURL.path]
        )
        try? FileManager.default.removeItem(at: AppPaths.launchAgentURL)
    }
}
