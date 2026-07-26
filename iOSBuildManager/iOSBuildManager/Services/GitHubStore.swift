import AppKit
import Foundation

/// Where the app is in the GitHub sign-in process.
enum GitHubConnection: Equatable {
    case signedOut
    /// Browser is open and we're waiting for the user to approve the code.
    case awaitingApproval(DeviceCodeGrant)
    case signedIn(GitHubUser)

    var user: GitHubUser? {
        if case .signedIn(let user) = self { return user }
        return nil
    }

    var isSignedIn: Bool { user != nil }
}

/// Owns GitHub authentication and the actions the UI offers. The access token
/// lives in the Keychain and is only held in memory while in use.
@MainActor
final class GitHubStore: ObservableObject {
    @Published private(set) var connection: GitHubConnection = .signedOut
    @Published private(set) var isWorking = false
    @Published var lastError: String?
    @Published var lastMessage: String?

    /// Status of the currently inspected project's working tree.
    @Published private(set) var status: GitStatus = .notARepository
    @Published private(set) var runs: [WorkflowRun] = []

    private var pollTask: Task<Void, Never>?
    private var token: String?

    // MARK: - Sign in / out

    /// Restores a previous session from the Keychain, or adopts a token from an
    /// authenticated `gh` CLI so users with it set up start signed in.
    func restore() async {
        if let stored = KeychainService.loadToken() {
            await adopt(token: stored, persist: false)
            if connection.isSignedIn { return }
        }
        if let cli = await GitHubAuthService.tokenFromGitHubCLI() {
            await adopt(token: cli, persist: true)
        }
    }

    /// Starts the OAuth device flow: fetches a code, opens the browser, and
    /// polls until the user approves.
    func signInWithBrowser(clientID: String) async {
        lastError = nil
        lastMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let grant = try await GitHubAuthService.requestDeviceCode(clientID: clientID)
            connection = .awaitingApproval(grant)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(grant.userCode, forType: .string)
            NSWorkspace.shared.open(grant.verificationURL)
            startPolling(clientID: clientID, grant: grant)
        } catch {
            lastError = error.localizedDescription
            connection = .signedOut
        }
    }

    func cancelSignIn() {
        pollTask?.cancel()
        pollTask = nil
        if case .awaitingApproval = connection { connection = .signedOut }
    }

    func signInWithGitHubCLI() async {
        isWorking = true
        defer { isWorking = false }
        guard let cli = await GitHubAuthService.tokenFromGitHubCLI() else {
            lastError = "The GitHub CLI isn't installed or isn't signed in. Run `gh auth login` in Terminal, then try again."
            return
        }
        await adopt(token: cli, persist: true)
    }

    func signOut() {
        pollTask?.cancel()
        pollTask = nil
        KeychainService.deleteToken()
        token = nil
        connection = .signedOut
        runs = []
        lastMessage = "Signed out."
    }

    private func startPolling(clientID: String, grant: DeviceCodeGrant) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var interval = UInt64(grant.interval)
            let deadline = Date().addingTimeInterval(TimeInterval(grant.expiresIn))

            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
                if Task.isCancelled { return }
                guard let self else { return }

                let result: DevicePollResult
                do {
                    result = try await GitHubAuthService.poll(clientID: clientID, deviceCode: grant.deviceCode)
                } catch {
                    await MainActor.run { self.lastError = error.localizedDescription }
                    return
                }

                switch result {
                case .pending:
                    continue
                case .slowDown:
                    interval += 5
                case .token(let value):
                    await self.adopt(token: value, persist: true)
                    return
                case .denied:
                    await MainActor.run {
                        self.lastError = "Authorization was denied on GitHub."
                        self.connection = .signedOut
                    }
                    return
                case .expired:
                    await MainActor.run {
                        self.lastError = "The code expired before it was approved. Try signing in again."
                        self.connection = .signedOut
                    }
                    return
                case .failed(let message):
                    await MainActor.run {
                        self.lastError = message
                        self.connection = .signedOut
                    }
                    return
                }
            }
        }
    }

    /// Validates a token by fetching the user, then keeps it if it works.
    private func adopt(token candidate: String, persist: Bool) async {
        do {
            let user = try await GitHubService.currentUser(token: candidate)
            token = candidate
            if persist { KeychainService.save(token: candidate) }
            connection = .signedIn(user)
            lastError = nil
            lastMessage = "Signed in as \(user.login)."
        } catch {
            if persist { lastError = error.localizedDescription }
            connection = .signedOut
        }
    }

    // MARK: - Repository status

    func refreshStatus(for project: Project?) async {
        guard let project else {
            status = .notARepository
            runs = []
            return
        }
        status = await GitService.status(at: project.workingDirectory)
        await refreshRuns()
    }

    func refreshRuns() async {
        guard let token, let repo = status.repoFullName else {
            runs = []
            return
        }
        do {
            runs = try await GitHubService.workflowRuns(token: token, repoFullName: repo)
        } catch {
            runs = []
        }
    }

    // MARK: - Actions

    /// Stages everything, commits, and pushes the current branch.
    func commitAndPush(project: Project, message: String) async {
        guard let token else { lastError = "Not signed in to GitHub."; return }
        guard let repo = status.repoFullName else {
            lastError = "This project has no GitHub remote yet. Publish it first."
            return
        }
        isWorking = true
        defer { isWorking = false }
        let directory = project.workingDirectory
        do {
            if status.hasChanges {
                try await GitService.stageAll(at: directory)
                try await GitService.commit(message: message, at: directory)
            }
            let branch = await GitService.currentBranch(at: directory)
            try await GitService.push(at: directory, branch: branch, repoFullName: repo, token: token, setUpstream: true)
            lastMessage = "Pushed to \(repo) (\(branch))."
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refreshStatus(for: project)
    }

    /// Creates a GitHub repository for a project and pushes the first commit.
    func publish(project: Project, name: String, isPrivate: Bool, description: String?) async {
        guard let token else { lastError = "Not signed in to GitHub."; return }
        isWorking = true
        defer { isWorking = false }
        let directory = project.workingDirectory
        do {
            if !status.isRepository {
                try await GitService.initRepository(at: directory)
            }
            let repo = try await GitHubService.createUserRepository(
                token: token, name: name, isPrivate: isPrivate, description: description
            )
            try await GitService.stageAll(at: directory)
            // An empty commit is fine here; a brand-new repo needs one commit
            // before it has a branch to push.
            try? await GitService.commit(message: "Initial commit", at: directory)
            try await GitService.setRemote(repoFullName: repo.fullName, at: directory)
            let branch = await GitService.currentBranch(at: directory)
            try await GitService.push(
                at: directory, branch: branch, repoFullName: repo.fullName, token: token, setUpstream: true
            )
            lastMessage = "Published to \(repo.fullName)."
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refreshStatus(for: project)
    }

    /// Publishes a GitHub release and attaches a built artifact.
    func publishRelease(tag: String, name: String, notes: String?, asset: URL?) async {
        guard let token else { lastError = "Not signed in to GitHub."; return }
        guard let repo = status.repoFullName else {
            lastError = "This project has no GitHub remote yet."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let release = try await GitHubService.createRelease(
                token: token, repoFullName: repo, tag: tag, name: name, body: notes, isDraft: false
            )
            if let asset, FileManager.default.fileExists(atPath: asset.path) {
                try await GitHubService.uploadReleaseAsset(
                    token: token, repoFullName: repo, releaseID: release.id, fileURL: asset
                )
            }
            lastMessage = "Released \(tag) on \(repo)."
            lastError = nil
            await refreshRuns()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Opens the repository on github.com.
    func openRepositoryInBrowser() {
        guard let repo = status.repoFullName,
              let url = URL(string: "https://github.com/\(repo)") else { return }
        NSWorkspace.shared.open(url)
    }
}
