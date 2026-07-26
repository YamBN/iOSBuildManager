import Foundation

/// The pending half of an OAuth device-flow sign-in: what to show the user
/// while the browser is open, plus what we need to keep polling.
struct DeviceCodeGrant: Sendable, Hashable {
    var deviceCode: String
    var userCode: String
    var verificationURL: URL
    var expiresIn: Int
    var interval: Int
}

/// Outcome of one poll of the token endpoint.
enum DevicePollResult: Sendable, Hashable {
    case pending
    case slowDown
    case token(String)
    case denied
    case expired
    case failed(String)
}

enum GitHubAuthError: LocalizedError {
    case notConfigured
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No GitHub OAuth client ID is configured. Add one in Settings → GitHub, or sign in with the GitHub CLI instead."
        case .network(let m): return m
        case .server(let m): return m
        }
    }
}

/// Signs in to GitHub with the OAuth **device flow**: the app opens a browser,
/// the user approves there, and the app polls until the token comes back.
///
/// Device flow is the right fit for a distributed desktop app because it needs
/// no client secret — a secret shipped inside an open-source app wouldn't be
/// secret. The client ID is public by design.
enum GitHubAuthService {
    static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    /// `repo` covers push/create/release; `workflow` allows reading Actions.
    static let scopes = "repo workflow read:org"

    // MARK: - Step 1: request a device code

    static func requestDeviceCode(clientID: String) async throws -> DeviceCodeGrant {
        guard !clientID.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw GitHubAuthError.notConfigured
        }
        var request = URLRequest(url: deviceCodeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["client_id": clientID, "scope": scopes])

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let grant = parseDeviceCode(data) else {
            throw GitHubAuthError.server(errorMessage(in: data) ?? "GitHub returned an unexpected device-code response.")
        }
        return grant
    }

    static func parseDeviceCode(_ data: Data) -> DeviceCodeGrant? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let uriString = json["verification_uri"] as? String,
              let uri = URL(string: uriString)
        else { return nil }
        return DeviceCodeGrant(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURL: uri,
            expiresIn: json["expires_in"] as? Int ?? 900,
            interval: max(1, json["interval"] as? Int ?? 5)
        )
    }

    // MARK: - Step 2: poll for the token

    static func poll(clientID: String, deviceCode: String) async throws -> DevicePollResult {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        return parsePoll(data)
    }

    static func parsePoll(_ data: Data) -> DevicePollResult {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failed("Unreadable response from GitHub.")
        }
        if let token = json["access_token"] as? String, !token.isEmpty {
            return .token(token)
        }
        switch json["error"] as? String {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "access_denied": return .denied
        case "expired_token": return .expired
        case let other?:
            return .failed((json["error_description"] as? String) ?? other)
        case nil:
            return .failed("GitHub returned no token and no error.")
        }
    }

    // MARK: - GitHub CLI fallback

    /// Reads a token from an already-authenticated `gh` CLI, so users who have
    /// it set up are signed in without registering anything.
    static func tokenFromGitHubCLI() async -> String? {
        guard let ghPath = await which("gh") else { return nil }
        guard let lines = try? await ShellRunner.collect(command: ghPath, arguments: ["auth", "token"]) else { return nil }
        let token = lines.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    static func which(_ tool: String) async -> String? {
        guard let lines = try? await ShellRunner.collect(command: "/usr/bin/which", arguments: [tool]) else { return nil }
        let path = lines.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    // MARK: - Helpers

    private static func formBody(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func errorMessage(in data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (json["error_description"] as? String) ?? (json["error"] as? String)
    }
}
