import Foundation

/// Pure helpers around `xcodebuild`: scheme discovery, argument construction,
/// locating the built `.app`, and reading its version metadata.
enum XcodeBuildService {
    static let xcodebuildPath = "/usr/bin/xcodebuild"

    /// Returns the list of schemes for a project/workspace via `xcodebuild -list`.
    static func schemes(for project: Project) async throws -> [String] {
        var args = ["-list"]
        args += project.isWorkspace ? ["-workspace", project.path] : ["-project", project.path]
        let lines = try await ShellRunner.collect(command: xcodebuildPath, arguments: args)
        return parseSchemes(lines: lines)
    }

    /// Parses the `Schemes:` section out of `xcodebuild -list` output.
    static func parseSchemes(lines: [String]) -> [String] {
        var inSchemes = false
        var schemes: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if lower.hasPrefix("schemes:") {
                inSchemes = true
                continue
            }
            guard inSchemes else { continue }
            if line.isEmpty {
                if !schemes.isEmpty { break } else { continue }
            }
            // Stop if a new labelled section appears (e.g. "Targets:").
            if line.contains(":") && !line.contains("/") {
                if !schemes.isEmpty { break } else { continue }
            }
            schemes.append(line)
        }
        return schemes
    }

    /// Builds the `xcodebuild` argument vector for a clean, controlled build.
    static func buildArguments(for project: Project) -> [String] {
        var args: [String] = []
        args += project.isWorkspace ? ["-workspace", project.path] : ["-project", project.path]
        if let scheme = project.selectedScheme { args += ["-scheme", scheme] }
        args += ["-configuration", project.configuration.rawValue]
        args += ["-destination", project.destination.xcodebuildDestination]
        args += ["-derivedDataPath", AppPaths.derivedData(for: project).path]
        args += ["-allowProvisioningUpdates", "build"]
        return args
    }

    /// The build products subfolder, e.g. `Release-iphoneos` or `Debug-iphonesimulator`.
    static func productsSubfolder(for project: Project) -> String {
        let platform: String
        switch project.destination {
        case .genericIOSSimulator: platform = "iphonesimulator"
        case .genericIOS, .connectedDevice: platform = "iphoneos"
        }
        return "\(project.configuration.rawValue)-\(platform)"
    }

    /// Locates the built `.app` inside the controlled DerivedData folder.
    static func locateApp(for project: Project) throws -> URL {
        let products = AppPaths.derivedData(for: project)
            .appendingPathComponent("Build/Products", isDirectory: true)
        let dir = products.appendingPathComponent(productsSubfolder(for: project), isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else {
            throw BuildError.noAppInProducts(dir)
        }
        let contents = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let apps = contents.filter { $0.pathExtension == "app" }
        guard let firstApp = apps.first else {
            throw BuildError.noAppInProducts(dir)
        }
        // Prefer the app whose name matches the project name; otherwise the first.
        if let match = apps.first(where: { $0.deletingPathExtension().lastPathComponent == project.name }) {
            return match
        }
        return firstApp
    }

    /// Returns the app's code-signing authority (e.g. "Apple Development: …"),
    /// "ad-hoc" for ad-hoc signatures, or nil when the bundle is unsigned.
    ///
    /// Unsigned IPAs are fine for SideStore/AltStore (they re-sign with the
    /// user's Apple ID) but cannot be installed directly via devicectl, so the
    /// build pipeline surfaces this as a warning rather than an error.
    static func codesignAuthority(at appURL: URL) async -> String? {
        guard let lines = try? await ShellRunner.collect(
            command: "/usr/bin/codesign",
            arguments: ["-dvv", appURL.path]
        ) else { return nil }

        if lines.contains(where: { $0.contains("code object is not signed") }) {
            return nil
        }
        if let authority = lines.first(where: { $0.hasPrefix("Authority=") }) {
            return String(authority.dropFirst("Authority=".count))
        }
        // Ad-hoc signatures have a Signature=adhoc line and no Authority lines.
        if lines.contains(where: { $0.contains("Signature=adhoc") }) {
            return "ad-hoc"
        }
        // Signed (CodeDirectory present) but authority unknown.
        if lines.contains(where: { $0.hasPrefix("CodeDirectory") }) {
            return "signed (unknown authority)"
        }
        return nil
    }

    /// Reads `CFBundleShortVersionString` and `CFBundleVersion` from a built app.
    static func readAppInfo(at appURL: URL) throws -> (version: String, buildNumber: String) {
        let plistURL = appURL.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { throw BuildError.appInfoReadFailed }
        let version = (plist["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        let build = (plist["CFBundleVersion"] as? String) ?? "0"
        return (version, build)
    }
}
