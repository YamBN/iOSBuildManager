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

        let intervalSeconds = max(settings.scheduledBuildIntervalDays, 1) * 86_400
        let plist: [String: Any] = [
            "Label": AppPaths.schedulerIdentifier,
            "ProgramArguments": ["/bin/sh", AppPaths.scheduledBuildScriptURL.path],
            "StartInterval": intervalSeconds,
            "RunAtLoad": false,
            "StandardOutPath": AppPaths.logsURL.appendingPathComponent("scheduler.log").path,
            "StandardErrorPath": AppPaths.logsURL.appendingPathComponent("scheduler.err").path
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: AppPaths.launchAgentURL, options: .atomic)

        _ = try await ShellRunner.collect(
            command: "/bin/launchctl",
            arguments: ["load", "-w", AppPaths.launchAgentURL.path]
        )
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
