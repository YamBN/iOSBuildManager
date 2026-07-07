import Foundation

/// Manages a LaunchAgent for optional scheduled builds (default: every 6 days).
enum SchedulerService {
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: AppPaths.launchAgentURL.path)
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
