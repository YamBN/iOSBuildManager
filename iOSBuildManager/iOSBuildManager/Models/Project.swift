import Foundation

/// What kind of buildable thing a project points at. Xcode projects and
/// workspaces build with `xcodebuild`; Swift packages build with `swift build`.
enum ProjectKind: String, Codable, Sendable, Hashable {
    case xcodeproj
    case xcworkspace
    case swiftPackage
}

/// A saved Xcode project or Swift package that the user can build repeatedly.
///
/// The path is stored as an absolute filesystem path. Because the app is not
/// sandboxed (it must shell out to `xcodebuild`/`swift`), we do not need
/// security-scoped bookmarks.
struct Project: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var isWorkspace: Bool
    /// Nil for projects saved by older versions (derived from `isWorkspace`).
    var kindRaw: String?
    var selectedScheme: String?
    var configuration: BuildConfiguration = .release
    var destination: BuildDestination = .genericIOS
    var createdAt: Date = .now
    var lastBuiltAt: Date?

    // Optional so projects saved by older versions still decode (synthesized
    // Codable treats a missing Optional key as nil rather than throwing).

    /// Platform detected from the scheme's build settings; nil until detected.
    var detectedPlatform: ProjectPlatform?
    /// User-chosen export format; nil means "use the platform default".
    var exportFormat: ExportFormat?
    /// Replaces the project name in the UI when non-empty.
    var displayNameOverride: String?
    /// Set once the user picks a custom icon; the file lives at
    /// `AppPaths.projectIcon(for:)`.
    var hasCustomIcon: Bool?

    var fileURL: URL { URL(fileURLWithPath: path) }

    /// The name to show: the user's override when set, otherwise the project's
    /// own name.
    var displayName: String {
        let trimmed = (displayNameOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : trimmed
    }

    /// A user-supplied icon that wins over the icon extracted from builds.
    var customIconURL: URL? {
        guard hasCustomIcon == true else { return nil }
        let url = AppPaths.projectIcon(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The build tooling this project uses. Falls back to the legacy
    /// `isWorkspace` flag for projects saved before packages were supported.
    var kind: ProjectKind {
        if let raw = kindRaw, let k = ProjectKind(rawValue: raw) { return k }
        return isWorkspace ? .xcworkspace : .xcodeproj
    }

    var isSwiftPackage: Bool { kind == .swiftPackage }

    /// Directory `xcodebuild`/`swift build` should run in. For a package that's
    /// the package folder itself; for a project it's the folder containing the
    /// `.xcodeproj`/`.xcworkspace`.
    var workingDirectory: URL {
        kind == .swiftPackage ? fileURL : fileURL.deletingLastPathComponent()
    }

    var projectTypeIcon: String {
        switch kind {
        case .xcworkspace: return "square.stack.3d.up"
        case .swiftPackage: return "shippingbox"
        case .xcodeproj: return "hammer"
        }
    }

    /// Detected platform, defaulting to `.unknown` before detection runs.
    var platform: ProjectPlatform { detectedPlatform ?? .unknown }

    var isMac: Bool { platform == .macOS }

    /// The export format to use: the user's choice if valid for the platform,
    /// otherwise the platform's default (IPA for iOS, DMG for macOS).
    var resolvedExportFormat: ExportFormat {
        let allowed = ExportFormat.formats(for: platform)
        if let chosen = exportFormat, allowed.contains(chosen) { return chosen }
        return allowed.first ?? .ipa
    }

    /// Detects `.xcworkspace` vs `.xcodeproj` from a path.
    static func isWorkspacePath(_ path: String) -> Bool {
        path.lowercased().hasSuffix(".xcworkspace")
    }
}
