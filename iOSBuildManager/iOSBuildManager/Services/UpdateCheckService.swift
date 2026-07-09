import Foundation

/// A GitHub release relevant to update checking.
struct AvailableUpdate: Equatable, Sendable, Identifiable {
    var id: String { version }
    var version: String       // e.g. "1.2.0" (tag's "v" prefix stripped)
    var releaseNotes: String
    var releaseURL: URL
}

/// Checks GitHub Releases for a newer version than the one currently running.
/// Local-only otherwise: this is the one network call the app ever makes, and
/// it only reads a public, unauthenticated endpoint — no telemetry is sent.
enum UpdateCheckService {
    private static let apiURL = URL(string: "https://api.github.com/repos/YamBN/iOSBuildManager/releases/latest")!

    /// Fetches the latest GitHub release and returns it if newer than `currentVersion`.
    /// Returns `nil` on any failure (offline, rate-limited, parse error) or when
    /// already up to date — failures should be silent, never block launch.
    static func checkForUpdate(currentVersion: String) async -> AvailableUpdate? {
        do {
            let (data, response) = try await URLSession.shared.data(from: apiURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteVersion = normalize(release.tag_name)
            guard isNewer(remoteVersion, than: currentVersion),
                  let url = URL(string: release.html_url)
            else { return nil }

            return AvailableUpdate(
                version: remoteVersion,
                releaseNotes: release.body ?? "",
                releaseURL: url
            )
        } catch {
            return nil
        }
    }

    /// Strips a leading "v" (GitHub tags are "v1.2.0"; AppVersion.version is "1.2.0").
    static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Dot-separated numeric version comparison ("1.2.0" vs "1.10.0" etc. —
    /// not a lexical string compare). Missing trailing components count as 0;
    /// non-numeric components compare as 0 rather than crashing.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = components(remote)
        let l = components(local)
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
    }
}
