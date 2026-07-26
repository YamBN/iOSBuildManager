import Foundation

struct GitHubUser: Sendable, Hashable {
    var login: String
    var name: String?
    var avatarURL: URL?
}

struct GitHubRepo: Sendable, Hashable, Identifiable {
    var id: Int
    var fullName: String     // "owner/name"
    var htmlURL: URL?
    var isPrivate: Bool
    var defaultBranch: String
}

struct WorkflowRun: Sendable, Hashable, Identifiable {
    var id: Int
    var name: String
    var status: String        // queued | in_progress | completed
    var conclusion: String?   // success | failure | cancelled | …
    var branch: String
    var htmlURL: URL?
    var createdAt: Date?

    /// Combined state for display: a run that's still going has no conclusion.
    var displayState: String { conclusion ?? status }

    var systemImage: String {
        switch displayState {
        case "success": return "checkmark.circle.fill"
        case "failure": return "xmark.circle.fill"
        case "cancelled": return "slash.circle.fill"
        case "in_progress", "queued": return "clock.fill"
        default: return "circle"
        }
    }
}

enum GitHubAPIError: LocalizedError {
    case notAuthenticated
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in to GitHub."
        case .http(let code, let message): return "GitHub API \(code): \(message)"
        }
    }
}

/// Thin GitHub REST client covering what the app needs: identity, repositories,
/// Actions runs, and releases.
enum GitHubService {
    static let apiRoot = URL(string: "https://api.github.com")!
    static let uploadRoot = "https://uploads.github.com"

    // MARK: - Identity

    static func currentUser(token: String) async throws -> GitHubUser {
        let data = try await get("/user", token: token)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let login = json["login"] as? String
        else { throw GitHubAPIError.http(0, "Unexpected /user response") }
        return GitHubUser(
            login: login,
            name: json["name"] as? String,
            avatarURL: (json["avatar_url"] as? String).flatMap(URL.init(string:))
        )
    }

    // MARK: - Repositories

    static func repositories(token: String) async throws -> [GitHubRepo] {
        let data = try await get("/user/repos?per_page=100&sort=updated", token: token)
        return parseRepos(data)
    }

    static func parseRepos(_ data: Data) -> [GitHubRepo] {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return array.compactMap(parseRepo)
    }

    static func parseRepo(_ json: [String: Any]) -> GitHubRepo? {
        guard let id = json["id"] as? Int, let fullName = json["full_name"] as? String else { return nil }
        return GitHubRepo(
            id: id,
            fullName: fullName,
            htmlURL: (json["html_url"] as? String).flatMap(URL.init(string:)),
            isPrivate: json["private"] as? Bool ?? false,
            defaultBranch: json["default_branch"] as? String ?? "main"
        )
    }

    /// Creates a repository under the authenticated user.
    static func createUserRepository(token: String, name: String, isPrivate: Bool, description: String?) async throws -> GitHubRepo {
        var body: [String: Any] = ["name": name, "private": isPrivate]
        if let description, !description.isEmpty { body["description"] = description }
        let data = try await send("POST", "/user/repos", token: token, json: body)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let repo = parseRepo(json)
        else { throw GitHubAPIError.http(0, "Unexpected create-repo response") }
        return repo
    }

    // MARK: - Actions

    static func workflowRuns(token: String, repoFullName: String, limit: Int = 10) async throws -> [WorkflowRun] {
        let data = try await get("/repos/\(repoFullName)/actions/runs?per_page=\(limit)", token: token)
        return parseWorkflowRuns(data)
    }

    static func parseWorkflowRuns(_ data: Data) -> [WorkflowRun] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let runs = root["workflow_runs"] as? [[String: Any]] else { return [] }
        let formatter = ISO8601DateFormatter()
        return runs.compactMap { json in
            guard let id = json["id"] as? Int else { return nil }
            return WorkflowRun(
                id: id,
                name: json["name"] as? String ?? "Workflow",
                status: json["status"] as? String ?? "",
                conclusion: json["conclusion"] as? String,
                branch: json["head_branch"] as? String ?? "",
                htmlURL: (json["html_url"] as? String).flatMap(URL.init(string:)),
                createdAt: (json["created_at"] as? String).flatMap { formatter.date(from: $0) }
            )
        }
    }

    // MARK: - Releases

    /// Creates a release and returns its id plus the asset upload URL template.
    static func createRelease(
        token: String,
        repoFullName: String,
        tag: String,
        name: String,
        body: String?,
        isDraft: Bool
    ) async throws -> (id: Int, htmlURL: URL?) {
        var payload: [String: Any] = [
            "tag_name": tag,
            "name": name,
            "draft": isDraft,
        ]
        if let body { payload["body"] = body }
        let data = try await send("POST", "/repos/\(repoFullName)/releases", token: token, json: payload)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = json["id"] as? Int
        else { throw GitHubAPIError.http(0, "Unexpected create-release response") }
        return (id, (json["html_url"] as? String).flatMap(URL.init(string:)))
    }

    /// Uploads a file as a release asset.
    static func uploadReleaseAsset(token: String, repoFullName: String, releaseID: Int, fileURL: URL) async throws {
        let name = fileURL.lastPathComponent
        guard var components = URLComponents(string: "\(uploadRoot)/repos/\(repoFullName)/releases/\(releaseID)/assets") else {
            throw GitHubAPIError.http(0, "Bad upload URL")
        }
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else { throw GitHubAPIError.http(0, "Bad upload URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request, token: token)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        try validate(response: response, data: data)
    }

    // MARK: - Transport

    private static func get(_ path: String, token: String) async throws -> Data {
        try await send("GET", path, token: token, json: nil)
    }

    private static func send(_ method: String, _ path: String, token: String, json: [String: Any]?) async throws -> Data {
        guard !token.isEmpty else { throw GitHubAPIError.notAuthenticated }
        guard let url = URL(string: apiRoot.absoluteString + path) else {
            throw GitHubAPIError.http(0, "Bad URL \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        applyHeaders(&request, token: token)
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private static func applyHeaders(_ request: inout URLRequest, token: String) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("iOSBuildManager", forHTTPHeaderField: "User-Agent")
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data))
                .flatMap { ($0 as? [String: Any])?["message"] as? String }
                ?? "request failed"
            throw GitHubAPIError.http(http.statusCode, message)
        }
    }
}
