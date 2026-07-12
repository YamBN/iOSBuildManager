import Foundation

/// Packages a built macOS `.app` for distribution, either as a zipped app or a
/// drag-to-Applications `.dmg`. Both paths use tools built into macOS (`ditto`,
/// `hdiutil`) so there is no runtime dependency to install.
enum MacPackager {
    /// Packages `appURL` into the chosen format and returns the written file.
    static func export(
        format: ExportFormat,
        appURL: URL,
        appName: String,
        version: String,
        buildNumber: String,
        outputFolder: URL,
        keepLatest: Bool
    ) async throws -> URL {
        switch format {
        case .appZip:
            return try await exportAppZip(appURL: appURL, appName: appName, version: version,
                                          buildNumber: buildNumber, outputFolder: outputFolder, keepLatest: keepLatest)
        case .dmg:
            return try await exportDMG(appURL: appURL, appName: appName, version: version,
                                       buildNumber: buildNumber, outputFolder: outputFolder, keepLatest: keepLatest)
        case .ipa:
            throw BuildError.packagingFailed("IPA is an iOS format; a macOS build cannot be packaged as an IPA.")
        }
    }

    // MARK: - .app zip

    private static func exportAppZip(
        appURL: URL, appName: String, version: String, buildNumber: String,
        outputFolder: URL, keepLatest: Bool
    ) async throws -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let versionedURL = outputFolder.appendingPathComponent(versionedName(appName, version, buildNumber, ext: "zip"))
        try? fm.removeItem(at: versionedURL)

        // ditto --keepParent stores the bundle as `AppName.app` inside the zip
        // and preserves symlinks / resource forks that a plain zip would lose.
        _ = try await ShellRunner.collect(
            command: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", appURL.path, versionedURL.path]
        )
        guard fm.fileExists(atPath: versionedURL.path) else {
            throw BuildError.packagingFailed("ditto did not produce \(versionedURL.lastPathComponent)")
        }

        if keepLatest { refreshLatest(named: "latest.zip", from: versionedURL, in: outputFolder) }
        return versionedURL
    }

    // MARK: - DMG

    private static func exportDMG(
        appURL: URL, appName: String, version: String, buildNumber: String,
        outputFolder: URL, keepLatest: Bool
    ) async throws -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        // Stage the app plus an /Applications symlink so the mounted DMG offers
        // the familiar drag-to-install layout.
        let staging = fm.temporaryDirectory.appendingPathComponent("dmg-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try fm.copyItem(at: appURL, to: staging.appendingPathComponent("\(appName).app"))
        try? fm.createSymbolicLink(atPath: staging.appendingPathComponent("Applications").path,
                                   withDestinationPath: "/Applications")

        let versionedURL = outputFolder.appendingPathComponent(versionedName(appName, version, buildNumber, ext: "dmg"))
        try? fm.removeItem(at: versionedURL)

        _ = try await ShellRunner.collect(
            command: "/usr/bin/hdiutil",
            arguments: ["create", "-volname", appName, "-srcfolder", staging.path,
                        "-ov", "-format", "UDZO", versionedURL.path]
        )
        guard fm.fileExists(atPath: versionedURL.path) else {
            throw BuildError.packagingFailed("hdiutil did not produce \(versionedURL.lastPathComponent)")
        }

        if keepLatest { refreshLatest(named: "latest.dmg", from: versionedURL, in: outputFolder) }
        return versionedURL
    }

    // MARK: - Helpers

    private static func versionedName(_ appName: String, _ version: String, _ buildNumber: String, ext: String) -> String {
        let safeName = appName.replacingOccurrences(of: " ", with: "_")
        return "\(safeName)-\(version)-\(buildNumber).\(ext)"
    }

    private static func refreshLatest(named: String, from source: URL, in folder: URL) {
        let fm = FileManager.default
        let latest = folder.appendingPathComponent(named)
        if fm.fileExists(atPath: latest.path) { try? fm.removeItem(at: latest) }
        try? fm.copyItem(at: source, to: latest)
    }
}
