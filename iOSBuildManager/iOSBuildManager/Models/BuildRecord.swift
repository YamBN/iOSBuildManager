import Foundation

/// A completed (or in-progress) build, persisted into build history.
struct BuildRecord: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var projectId: UUID
    var projectName: String
    var scheme: String
    var configuration: String
    var version: String
    var buildNumber: String
    var date: Date
    var sizeBytes: Int64
    var status: BuildStatus
    var outputURL: URL
    var appPath: String?
    var durationSeconds: Double
    var log: String?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var formattedDuration: String {
        if durationSeconds < 1 { return "<1s" }
        if durationSeconds < 60 {
            return String(format: "%.0fs", durationSeconds)
        }
        let m = Int(durationSeconds) / 60
        let s = Int(durationSeconds) % 60
        return String(format: "%dm %ds", m, s)
    }

    var fileName: String { outputURL.lastPathComponent }
}
