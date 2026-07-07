import Foundation

/// A saved Xcode project that the user can build repeatedly.
///
/// The path is stored as an absolute filesystem path. Because the app is not
/// sandboxed (it must shell out to `xcodebuild`), we do not need
/// security-scoped bookmarks.
struct Project: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var isWorkspace: Bool
    var selectedScheme: String?
    var configuration: BuildConfiguration = .release
    var destination: BuildDestination = .genericIOS
    var createdAt: Date = .now
    var lastBuiltAt: Date?

    var fileURL: URL { URL(fileURLWithPath: path) }

    var displayName: String { name }

    var projectTypeIcon: String {
        isWorkspace ? "square.stack.3d.up" : "hammer"
    }

    /// Detects `.xcworkspace` vs `.xcodeproj` from a path.
    static func isWorkspacePath(_ path: String) -> Bool {
        path.lowercased().hasSuffix(".xcworkspace")
    }
}
