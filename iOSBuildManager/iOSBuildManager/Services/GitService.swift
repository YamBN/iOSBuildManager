import Foundation

/// Snapshot of a working tree, as shown in the GitHub section.
struct GitStatus: Sendable, Hashable {
    var isRepository: Bool
    var branch: String
    var changedFiles: [String]
    var remoteURL: String?
    var aheadCount: Int

    var hasChanges: Bool { !changedFiles.isEmpty }

    /// "owner/name" parsed from the origin remote, when there is one.
    var repoFullName: String? { remoteURL.flatMap(GitService.repoFullName(fromRemote:)) }

    static let notARepository = GitStatus(
        isRepository: false, branch: "", changedFiles: [], remoteURL: nil, aheadCount: 0
    )
}

/// Runs `git` in a project directory. Read-only queries are safe to call
/// freely; anything that writes history or contacts the remote is only invoked
/// from an explicit, confirmed user action in the UI.
enum GitService {
    static let gitPath = "/usr/bin/git"

    // MARK: - Queries

    static func status(at directory: URL) async -> GitStatus {
        guard let inside = try? await run(["rev-parse", "--is-inside-work-tree"], at: directory),
              inside.joined().contains("true")
        else { return .notARepository }

        let branch = (try? await run(["rev-parse", "--abbrev-ref", "HEAD"], at: directory))?
            .joined().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let porcelain = (try? await run(["status", "--porcelain"], at: directory)) ?? []
        let remote = (try? await run(["remote", "get-url", "origin"], at: directory))?
            .joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let ahead = (try? await run(["rev-list", "--count", "@{u}..HEAD"], at: directory))?
            .joined().trimmingCharacters(in: .whitespacesAndNewlines)

        return GitStatus(
            isRepository: true,
            branch: branch,
            changedFiles: parseChangedFiles(porcelain),
            remoteURL: (remote?.isEmpty ?? true) ? nil : remote,
            aheadCount: Int(ahead ?? "") ?? 0
        )
    }

    /// Parses `git status --porcelain` lines into display paths.
    static func parseChangedFiles(_ lines: [String]) -> [String] {
        lines.compactMap { raw in
            // Format is "XY <path>"; the two status columns are always present.
            guard raw.count > 3 else { return nil }
            let path = String(raw.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return path.isEmpty ? nil : path
        }
    }

    /// Extracts "owner/name" from an https or ssh GitHub remote URL.
    static func repoFullName(fromRemote remote: String) -> String? {
        var trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(".git") { trimmed = String(trimmed.dropLast(4)) }

        if let range = trimmed.range(of: "github.com") {
            // Covers https://github.com/owner/name and git@github.com:owner/name
            var path = String(trimmed[range.upperBound...])
            path = path.trimmingCharacters(in: CharacterSet(charactersIn: ":/"))
            let parts = path.split(separator: "/").map(String.init)
            if parts.count >= 2 { return "\(parts[0])/\(parts[1])" }
        }
        return nil
    }

    // MARK: - Mutations (only from explicit user actions)

    static func initRepository(at directory: URL, defaultBranch: String = "main") async throws {
        try await runStrict(["init", "-b", defaultBranch], at: directory)
    }

    static func stageAll(at directory: URL) async throws {
        try await runStrict(["add", "-A"], at: directory)
    }

    static func commit(message: String, at directory: URL) async throws {
        try await runStrict(["commit", "-m", message], at: directory)
    }

    /// Points `origin` at the public https URL (never one containing a token).
    static func setRemote(repoFullName: String, at directory: URL) async throws {
        let url = publicRemote(repoFullName: repoFullName)
        let existing = try? await run(["remote", "get-url", "origin"], at: directory)
        let hasOrigin = !((existing?.joined() ?? "").contains("No such remote"))
            && !((existing?.joined() ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        try await runStrict(["remote", hasOrigin ? "set-url" : "add", "origin", url], at: directory)
    }

    /// Pushes using a one-shot authenticated URL so no credential helper is
    /// needed and the token is never written into `.git/config`.
    static func push(at directory: URL, branch: String, repoFullName: String, token: String, setUpstream: Bool) async throws {
        var args = ["push"]
        if setUpstream { args += ["-u"] }
        args += [authenticatedRemote(repoFullName: repoFullName, token: token), branch]
        try await runStrict(args, at: directory, redacting: [token])
    }

    static func currentBranch(at directory: URL) async -> String {
        let name = (try? await run(["rev-parse", "--abbrev-ref", "HEAD"], at: directory))?
            .joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty, name != "HEAD" else { return "main" }
        return name
    }

    // MARK: - Plumbing

    /// An https remote carrying the token, used only as a transient `git push`
    /// argument — never stored as `origin`.
    static func authenticatedRemote(repoFullName: String, token: String) -> String {
        "https://x-access-token:\(token)@github.com/\(repoFullName).git"
    }

    static func publicRemote(repoFullName: String) -> String {
        "https://github.com/\(repoFullName).git"
    }

    /// Removes secrets from text that may be shown to the user or logged.
    static func redact(_ text: String, secrets: [String]) -> String {
        var output = text
        for secret in secrets where !secret.isEmpty {
            output = output.replacingOccurrences(of: secret, with: "***")
        }
        return output
    }

    /// Non-throwing run used for queries, where a non-zero exit is a normal
    /// answer (e.g. "not a repository").
    @discardableResult
    private static func run(_ arguments: [String], at directory: URL) async throws -> [String] {
        try await ShellRunner.collect(command: gitPath, arguments: arguments, cwd: directory)
    }

    /// Throwing run used for mutations, so a failed commit or push surfaces as
    /// an error with git's own message rather than passing silently.
    @discardableResult
    private static func runStrict(_ arguments: [String], at directory: URL, redacting secrets: [String] = []) async throws -> [String] {
        var lines: [String] = []
        do {
            for try await line in ShellRunner.stream(command: gitPath, arguments: arguments, cwd: directory, throwOnNonZero: true) {
                lines.append(line)
            }
            return lines
        } catch {
            let detail = redact(lines.suffix(6).joined(separator: "\n"), secrets: secrets)
            let command = redact("git " + arguments.joined(separator: " "), secrets: secrets)
            throw GitError.commandFailed(command: command, detail: detail)
        }
    }
}

enum GitError: LocalizedError {
    case commandFailed(command: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let detail):
            return detail.isEmpty ? "`\(command)` failed." : detail
        }
    }
}
