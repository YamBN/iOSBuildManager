import Foundation

/// Packages a built `.app` into an `.ipa` (Payload folder + zip), writes a
/// versioned file into the output folder, and optionally refreshes `latest.ipa`.
enum IPAPackager {
    /// Creates `Payload/AppName.app`, zips it into a versioned `.ipa`, and
    /// optionally copies it to `latest.ipa`. Returns the versioned IPA URL.
    static func pack(
        appURL: URL,
        appName: String,
        version: String,
        buildNumber: String,
        outputFolder: URL,
        keepLatest: Bool
    ) async throws -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let temp = fm.temporaryDirectory.appendingPathComponent("ipa-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        let payload = temp.appendingPathComponent("Payload", isDirectory: true)
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)
        let destApp = payload.appendingPathComponent("\(appName).app")
        try fm.copyItem(at: appURL, to: destApp)

        let safeName = appName.replacingOccurrences(of: " ", with: "_")
        let versionedName = "\(safeName)-\(version)-\(buildNumber).ipa"
        let versionedURL = outputFolder.appendingPathComponent(versionedName)

        _ = try await ShellRunner.collect(
            command: "/usr/bin/zip",
            arguments: ["-rXq", versionedURL.path, "Payload"],
            cwd: temp
        )

        guard fm.fileExists(atPath: versionedURL.path) else {
            throw BuildError.packagingFailed("zip did not produce \(versionedName)")
        }

        if keepLatest {
            let latest = outputFolder.appendingPathComponent("latest.ipa")
            if fm.fileExists(atPath: latest.path) { try? fm.removeItem(at: latest) }
            try? fm.copyItem(at: versionedURL, to: latest)
        }

        return versionedURL
    }

    /// File size in bytes for a URL, or 0 when unavailable.
    static func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}

/// Removes old versioned IPAs for a project, keeping only the most recent N.
enum AutoClean {
    static func run(settings: AppSettings, projectName: String) {
        guard settings.autoCleanOldBuilds else { return }
        runNow(settings: settings, projectName: projectName)
    }

    /// Deletes stale versioned IPAs for a project regardless of the auto-clean
    /// setting, for use by an explicit user-triggered "Clean Old Builds" action.
    static func runNow(settings: AppSettings, projectName: String) {
        let keep = max(settings.keepBuildHistoryCount, 1)
        let fm = FileManager.default
        let safeName = projectName.replacingOccurrences(of: " ", with: "_")
        guard let entries = try? fm.contentsOfDirectory(at: settings.outputURL, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }

        let prefix = "\(safeName)-"
        var ipas = entries.filter { $0.pathExtension == "ipa" && $0.lastPathComponent.hasPrefix(prefix) }
        ipas.sort { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
        for stale in ipas.dropFirst(keep) {
            try? fm.removeItem(at: stale)
        }
    }
}
