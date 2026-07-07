import AppKit
import Foundation
import UniformTypeIdentifiers

/// Discovers and imports provisioning profiles from
/// `~/Library/MobileDevice/Provisioning Profiles`.
@MainActor
final class ProvisioningProfileStore: ObservableObject {
    @Published private(set) var profiles: [ProvisioningProfile] = []
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?

    var primaryTeamName: String? { profiles.first?.teamName }
    var primaryTeamId: String? { profiles.first?.teamId }

    func refresh() async {
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }
        do {
            profiles = try await Self.scan()
        } catch {
            lastError = error.localizedDescription
            profiles = []
        }
    }

    /// Presents an open panel and imports the chosen `.mobileprovision` file(s)
    /// into the standard MobileDevice provisioning profiles folder.
    func importProfile() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mobileprovision")].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            do {
                try await Self.install(from: url)
            } catch {
                lastError = error.localizedDescription
            }
        }
        await refresh()
    }

    func remove(_ profile: ProvisioningProfile) {
        try? FileManager.default.removeItem(at: profile.fileURL)
        profiles.removeAll { $0.id == profile.id }
    }

    // MARK: - Static helpers

    private nonisolated static var directory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/MobileDevice/Provisioning Profiles", isDirectory: true)
    }

    nonisolated static func scan() async throws -> [ProvisioningProfile] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var results: [ProvisioningProfile] = []
        for url in entries where url.pathExtension == "mobileprovision" {
            if let profile = try? await parse(fileURL: url) {
                results.append(profile)
            }
        }
        return results.sorted { ($0.expirationDate ?? .distantPast) > ($1.expirationDate ?? .distantPast) }
    }

    nonisolated static func install(from sourceURL: URL) async throws {
        let profile = try await parse(fileURL: sourceURL)
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(profile.uuid).mobileprovision")
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: sourceURL, to: destination)
    }

    /// Decodes a `.mobileprovision` (a CMS/PKCS#7-signed plist) via `security cms -D`.
    nonisolated static func parse(fileURL: URL) async throws -> ProvisioningProfile {
        let data = try await decodedPlistData(at: fileURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw BuildError.generic("Could not read provisioning profile at \(fileURL.lastPathComponent).")
        }
        let name = plist["Name"] as? String ?? fileURL.deletingPathExtension().lastPathComponent
        let uuid = plist["UUID"] as? String ?? fileURL.deletingPathExtension().lastPathComponent
        let teamName = plist["TeamName"] as? String ?? "Unknown Team"
        let teamId = (plist["TeamIdentifier"] as? [String])?.first ?? "—"
        let expiration = plist["ExpirationDate"] as? Date

        let entitlements = plist["Entitlements"] as? [String: Any]
        let getTaskAllow = (entitlements?["get-task-allow"] as? Bool) ?? false
        let provisionsAllDevices = (plist["ProvisionsAllDevices"] as? Bool) ?? false
        let hasDevices = (plist["ProvisionedDevices"] as? [String])?.isEmpty == false

        let kind: ProvisioningProfile.Kind
        if getTaskAllow {
            kind = .development
        } else if provisionsAllDevices {
            kind = .enterprise
        } else if hasDevices {
            kind = .adHoc
        } else {
            kind = .appStore
        }

        return ProvisioningProfile(
            name: name,
            uuid: uuid,
            teamName: teamName,
            teamId: teamId,
            expirationDate: expiration,
            kind: kind,
            fileURL: fileURL
        )
    }

    private nonisolated static func decodedPlistData(at fileURL: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
                process.arguments = ["cms", "-D", "-i", fileURL.path]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: BuildError.generic("Failed to decode \(fileURL.lastPathComponent)."))
                }
            }
        }
    }
}
