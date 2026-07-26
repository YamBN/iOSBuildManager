import AppKit
import SwiftUI

/// Sign in to GitHub and manage the selected project's repository: see what
/// changed, commit and push, publish a brand-new repo, watch Actions, and cut a
/// release with the latest build attached.
struct GitHubView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var github: GitHubStore
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var history: BuildHistoryStore

    @State private var commitMessage = ""
    @State private var showPublishSheet = false
    @State private var showReleaseSheet = false
    @State private var confirmingPush = false

    private var project: Project? { model.selectedProject ?? projects.projects.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header

                if github.connection.isSignedIn {
                    accountCard
                    repositoryCard
                    if github.status.repoFullName != nil {
                        actionsCard
                        releaseCard
                    }
                } else {
                    signInCard
                }

                if let error = github.lastError {
                    banner(error, color: .red, icon: "exclamationmark.triangle.fill")
                }
                if let message = github.lastMessage, github.lastError == nil {
                    banner(message, color: .green, icon: "checkmark.circle.fill")
                }
            }
            .padding(Theme.spacing)
        }
        .navigationTitle("GitHub")
        .task { await github.restore() }
        .task(id: project?.id) { await github.refreshStatus(for: project) }
        .sheet(isPresented: $showPublishSheet) {
            PublishRepoSheet(project: project)
        }
        .sheet(isPresented: $showReleaseSheet) {
            PublishReleaseSheet()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("GitHub").font(.largeTitle.weight(.bold))
                Text("Publish and manage this project's repository")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if github.isWorking { ProgressView().controlSize(.small) }
        }
    }

    // MARK: - Sign in

    private var signInCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Connect your account", systemImage: "person.badge.key")

                if case .awaitingApproval(let grant) = github.connection {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Enter this code on GitHub — it's already copied to your clipboard.")
                            .font(.callout)
                        HStack(spacing: 12) {
                            Text(grant.userCode)
                                .font(.system(.title, design: .monospaced).weight(.bold))
                                .textSelection(.enabled)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Button("Open GitHub Again") { NSWorkspace.shared.open(grant.verificationURL) }
                            Button("Cancel") { github.cancelSignIn() }
                        }
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for you to approve it in the browser…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Sign in to push commits, publish repositories, watch Actions, and cut releases without leaving the app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            Task { await github.signInWithBrowser(clientID: settings.settings.githubClientID) }
                        } label: {
                            Label("Sign in with Browser", systemImage: "safari")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(settings.settings.githubClientID.trimmingCharacters(in: .whitespaces).isEmpty || github.isWorking)

                        Button {
                            Task { await github.signInWithGitHubCLI() }
                        } label: {
                            Label("Use GitHub CLI", systemImage: "terminal")
                        }
                        .disabled(github.isWorking)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("OAuth Client ID")
                            .font(.subheadline.weight(.medium))
                        TextField("Iv1.0123456789abcdef", text: Binding(
                            get: { settings.settings.githubClientID },
                            set: { settings.settings.githubClientID = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                        Text("Browser sign-in uses GitHub's device flow, which needs an OAuth App ID. Create one at github.com/settings/developers with “Device flow” enabled — no client secret is needed, so the ID is safe to keep here. If you'd rather not, the GitHub CLI option works with no setup.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Account

    @ViewBuilder
    private var accountCard: some View {
        if let user = github.connection.user {
            GlassPanel {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name ?? user.login).font(.headline)
                        Text("@\(user.login)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sign Out") { github.signOut() }
                }
            }
        }
    }

    // MARK: - Repository

    private var repositoryCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Repository", systemImage: "folder.badge.gearshape")

                if project == nil {
                    Text("Add a project in Settings to manage it here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if !github.status.isRepository {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This project isn't a git repository yet.")
                            .font(.callout)
                        Button {
                            showPublishSheet = true
                        } label: {
                            Label("Publish to GitHub…", systemImage: "arrow.up.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    infoRow(label: "Branch", value: github.status.branch, icon: "arrow.triangle.branch")

                    if let repo = github.status.repoFullName {
                        HStack(spacing: 8) {
                            Image(systemName: "link").foregroundStyle(.secondary).frame(width: 18)
                            Text(repo).font(.callout)
                            Spacer()
                            Button("Open on GitHub") { github.openRepositoryInBrowser() }
                                .buttonStyle(.borderless)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No GitHub remote yet.").font(.callout).foregroundStyle(.secondary)
                            Button {
                                showPublishSheet = true
                            } label: {
                                Label("Publish to GitHub…", systemImage: "arrow.up.circle")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    Divider()

                    if github.status.hasChanges {
                        Text("\(github.status.changedFiles.count) uncommitted change\(github.status.changedFiles.count == 1 ? "" : "s")")
                            .font(.subheadline.weight(.medium))
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(github.status.changedFiles.prefix(6), id: \.self) { file in
                                Text(file)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            if github.status.changedFiles.count > 6 {
                                Text("+ \(github.status.changedFiles.count - 6) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if github.status.aheadCount > 0 {
                        Text("\(github.status.aheadCount) commit\(github.status.aheadCount == 1 ? "" : "s") ready to push")
                            .font(.subheadline.weight(.medium))
                    } else {
                        Label("Everything is committed and pushed", systemImage: "checkmark.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if github.status.repoFullName != nil {
                        HStack(spacing: 8) {
                            TextField("Commit message", text: $commitMessage)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                confirmingPush = true
                            } label: {
                                Label("Commit & Push", systemImage: "arrow.up.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(pushDisabled)
                        }
                        .confirmationDialog(
                            "Push to \(github.status.repoFullName ?? "GitHub")?",
                            isPresented: $confirmingPush,
                            titleVisibility: .visible
                        ) {
                            Button("Push") {
                                Task {
                                    guard let project else { return }
                                    await github.commitAndPush(project: project, message: commitMessage)
                                    commitMessage = ""
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This publishes your commits to the \(github.status.branch) branch on GitHub.")
                        }
                    }

                    Button {
                        Task { await github.refreshStatus(for: project) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var pushDisabled: Bool {
        if github.isWorking { return true }
        let hasSomethingToSend = github.status.hasChanges || github.status.aheadCount > 0
        guard hasSomethingToSend else { return true }
        // A message is only required when there are changes to commit.
        if github.status.hasChanges {
            return commitMessage.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return false
    }

    // MARK: - Actions

    private var actionsCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Actions", systemImage: "bolt.horizontal")
                    Spacer()
                    Button {
                        Task { await github.refreshRuns() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }

                if github.runs.isEmpty {
                    Text("No workflow runs found.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(github.runs.prefix(6)) { run in
                        HStack(spacing: 10) {
                            Image(systemName: run.systemImage)
                                .foregroundStyle(color(for: run.displayState))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(run.name).font(.callout).lineLimit(1)
                                Text("\(run.branch) • \(run.displayState)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let url = run.htmlURL {
                                Button("View") { NSWorkspace.shared.open(url) }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
    }

    private func color(for state: String) -> Color {
        switch state {
        case "success": return .green
        case "failure": return .red
        case "in_progress", "queued": return .orange
        default: return .secondary
        }
    }

    // MARK: - Release

    private var releaseCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Releases", systemImage: "shippingbox")
                if let latest = history.mostRecentSuccess {
                    Text("Latest build: \(latest.projectName) \(latest.version) (\(latest.buildNumber)) • \(latest.fileName)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No successful build yet — build the project to attach an artifact.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button {
                    showReleaseSheet = true
                } label: {
                    Label("Publish Release…", systemImage: "paperplane")
                }
                .buttonStyle(.bordered)
                .disabled(history.mostRecentSuccess == nil)
            }
        }
    }

    // MARK: - Bits

    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            Text(label).font(.subheadline.weight(.medium))
            Text(value).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func banner(_ text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Publish repository

private struct PublishRepoSheet: View {
    let project: Project?

    @EnvironmentObject private var github: GitHubStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Publish to GitHub").font(.title2.weight(.bold))
            Text("Creates a new repository under your account and pushes this project to it.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Form {
                TextField("Repository name", text: $name)
                TextField("Description (optional)", text: $description)
                Picker("Visibility", selection: $isPrivate) {
                    Text("Private").tag(true)
                    Text("Public").tag(false)
                }
                .pickerStyle(.segmented)
            }

            if isPrivate == false {
                Label("A public repository is visible to everyone on the internet.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Publish") {
                    guard let project else { return }
                    let repoName = name.trimmingCharacters(in: .whitespaces)
                    Task {
                        await github.publish(
                            project: project,
                            name: repoName,
                            isPrivate: isPrivate,
                            description: description.isEmpty ? nil : description
                        )
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || project == nil || github.isWorking)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { if name.isEmpty { name = project?.name ?? "" } }
    }
}

// MARK: - Publish release

private struct PublishReleaseSheet: View {
    @EnvironmentObject private var github: GitHubStore
    @EnvironmentObject private var history: BuildHistoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var tag = ""
    @State private var name = ""
    @State private var notes = ""
    @State private var attachArtifact = true

    private var latest: BuildRecord? { history.mostRecentSuccess }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Publish Release").font(.title2.weight(.bold))
            if let repo = github.status.repoFullName {
                Text("Creates a release on \(repo).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("Tag", text: $tag)
                TextField("Title", text: $name)
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                if let latest {
                    Toggle("Attach \(latest.fileName)", isOn: $attachArtifact)
                }
            }

            Label("This publishes a release visible to anyone who can see the repository.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Publish") {
                    Task {
                        await github.publishRelease(
                            tag: tag.trimmingCharacters(in: .whitespaces),
                            name: name.isEmpty ? tag : name,
                            notes: notes.isEmpty ? nil : notes,
                            asset: attachArtifact ? latest?.outputURL : nil
                        )
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(tag.trimmingCharacters(in: .whitespaces).isEmpty || github.isWorking)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if tag.isEmpty, let latest { tag = "v\(latest.version)" }
            if name.isEmpty { name = tag }
        }
    }
}
