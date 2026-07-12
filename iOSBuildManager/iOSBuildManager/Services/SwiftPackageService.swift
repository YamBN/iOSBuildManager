import Foundation

/// Builds Swift packages (`Package.swift`) with `swift build` and wraps the
/// resulting command-line executable into a minimal `.app` bundle so it can be
/// packaged as a `.dmg` / `.zip` like any other Mac app.
enum SwiftPackageService {
    static let swiftPath = "/usr/bin/swift"

    /// Executable product names declared in the package, used as build targets
    /// (surfaced in the UI where a project would list schemes).
    static func executableProducts(atPackageDir dir: URL) async throws -> [String] {
        let json = try await ShellRunner.collect(
            command: swiftPath,
            arguments: ["package", "dump-package"],
            cwd: dir
        ).joined(separator: "\n")
        return parseExecutableProducts(dumpPackageJSON: Data(json.utf8))
    }

    /// Parses `swift package dump-package` output for executable product names.
    static func parseExecutableProducts(dumpPackageJSON data: Data) -> [String] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let products = root["products"] as? [[String: Any]] else { return [] }
        var names: [String] = []
        for product in products {
            guard let name = product["name"] as? String else { continue }
            // The product "type" is an object keyed by kind, e.g. {"executable": null}.
            if let type = product["type"] as? [String: Any], type.keys.contains("executable") {
                names.append(name)
            }
        }
        return names
    }

    /// `swift build` arguments for a product in a given configuration.
    static func buildArguments(product: String?, configuration: BuildConfiguration) -> [String] {
        var args = ["build", "-c", configuration == .debug ? "debug" : "release"]
        if let product { args += ["--product", product] }
        return args
    }

    /// The directory `swift build` places products in for a configuration.
    static func binPath(packageDir: URL, configuration: BuildConfiguration) async throws -> URL {
        let lines = try await ShellRunner.collect(
            command: swiftPath,
            arguments: ["build", "-c", configuration == .debug ? "debug" : "release", "--show-bin-path"],
            cwd: packageDir
        )
        guard let path = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw BuildError.packagingFailed("Could not determine swift build output path.")
        }
        return URL(fileURLWithPath: path.trimmingCharacters(in: .whitespaces))
    }

    /// Wraps a built executable in a minimal double-clickable `.app` bundle and
    /// returns its URL. The bundle is created fresh under `containerDir`.
    static func wrapExecutableInApp(
        executableURL: URL,
        appName: String,
        bundleIdentifier: String,
        version: String,
        buildNumber: String,
        containerDir: URL
    ) throws -> URL {
        let fm = FileManager.default
        let appURL = containerDir.appendingPathComponent("\(appName).app")
        if fm.fileExists(atPath: appURL.path) { try fm.removeItem(at: appURL) }

        let macOSDir = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macOSDir, withIntermediateDirectories: true)

        let destExe = macOSDir.appendingPathComponent(appName)
        try fm.copyItem(at: executableURL, to: destExe)

        let plist: [String: Any] = [
            "CFBundleName": appName,
            "CFBundleDisplayName": appName,
            "CFBundleExecutable": appName,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": buildNumber,
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSMinimumSystemVersion": "13.0",
            "NSHighResolutionCapable": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: appURL.appendingPathComponent("Contents/Info.plist"))

        return appURL
    }
}
