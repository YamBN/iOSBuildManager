import Combine
import Foundation
import SwiftUI

/// The single source of truth for app-wide state. Owns all stores and the
/// build engine, and exposes high-level actions used by views.
@MainActor
final class AppModel: ObservableObject {
    @Published var selection: SidebarSection = .dashboard
    @Published var selectedProjectId: UUID?
    @Published var availableUpdate: AvailableUpdate?
    /// Whole-percent build progress, mirrored into the menu bar so it's visible
    /// without opening the panel. Nil when no build is running.
    @Published private(set) var buildPercent: Int?

    let settings: SettingsStore
    let projects: ProjectStore
    let history: BuildHistoryStore
    let devices: DeviceStore
    let engine: BuildEngine
    let buildQueue: BuildQueue
    let profiles: ProvisioningProfileStore
    let certificates: CertificateStore
    let branding: BrandingStore
    let github: GitHubStore

    private var cancellables: Set<AnyCancellable> = []

    init() {
        AppPaths.ensureDirectories()
        self.settings = SettingsStore()
        self.projects = ProjectStore()
        self.history = BuildHistoryStore()
        self.devices = DeviceStore()
        self.engine = BuildEngine()
        self.buildQueue = BuildQueue(directory: AppPaths.supportURL.appendingPathComponent("Queue"))
        self.profiles = ProvisioningProfileStore()
        self.certificates = CertificateStore()
        self.branding = BrandingStore()
        self.github = GitHubStore()

        // Scene-level modifiers (preferredColorScheme, MenuBarExtra insertion)
        // read nested settings through `model`, so forward the store's change
        // events or the scenes never re-evaluate when a setting flips.
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Views showing a project's icon read it through this store.
        branding.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Drives the menu bar's live percentage. The engine only calls this
        // when the whole number changes, so the scene re-evaluates at most
        // once per percent instead of on every log line.
        engine.onProgressPercent = { [weak self] percent in
            self?.buildPercent = percent
        }

        buildQueue.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        buildQueue.resolve = { [weak self] request in
            guard let self else { throw BuildError.packagingFailed("Application unavailable.") }
            return try self.resolveBuildRequest(request)
        }
        buildQueue.run = { [weak self] job in self?.runQueuedBuild(job) }
        // Hosted tests must not consume a developer's real queue or rewrite launchd.
        guard !AppPaths.isTesting else { return }
        buildQueue.start()

        // Migrate LaunchAgents installed under old bundle identifiers; if one
        // existed and scheduling is still on, re-install it under the current
        // identifier so scheduled builds keep working after the rename.
        Task { [weak self] in
            let hadLegacy = await SchedulerService.removeLegacyAgents()
            // Reinstall an enabled schedule so older direct-build scripts also
            // go through the single queue. Preserve the user's chosen cadence.
            if hadLegacy || self?.settings.settings.scheduledBuildsEnabled == true {
                await self?.applySchedulerSettings()
            }
        }
    }

    // MARK: - Build

    func startBuild(for projectId: UUID) {
        guard let project = projects.project(with: projectId) else { return }
        submitBuild(project: project)
    }

    private func submitBuild(project: Project, clean: Bool = false) {
        do {
            try buildQueue.submit(BuildRequest(projectId: project.id, clean: clean))
        } catch {
            NotificationService.post(title: "Could not queue build", body: error.localizedDescription)
        }
    }

    private func resolveBuildRequest(_ request: BuildRequest) throws -> (Project, AppSettings) {
        var project: Project
        if let id = request.projectId, request.projectPath == nil,
           let saved = projects.project(with: id) {
            project = saved
        } else if request.projectId == nil, let path = request.projectPath,
                  path.hasPrefix("/"), FileManager.default.fileExists(atPath: path),
                  let location = Self.resolveProjectLocation(URL(fileURLWithPath: path)) {
            if let saved = projects.projects.first(where: { $0.path == location.path }) {
                project = saved
            } else {
                project = Project(name: location.name, path: location.path,
                                  isWorkspace: location.kind == .xcworkspace)
                project.kindRaw = location.kind.rawValue
                if location.kind == .swiftPackage {
                    project.detectedPlatform = .macOS
                    project.destination = .macOS
                }
            }
        } else {
            throw BuildError.packagingFailed("Supply an existing project ID or an absolute project path.")
        }
        guard FileManager.default.fileExists(atPath: project.path) else {
            throw BuildError.packagingFailed("Project path does not exist.")
        }
        if let scheme = request.scheme { project.selectedScheme = scheme }
        guard let scheme = project.selectedScheme, !scheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BuildError.packagingFailed("A scheme/product is required. Pass --scheme or configure the project in the app.")
        }
        if let raw = request.configuration {
            guard let configuration = BuildConfiguration(rawValue: raw) else {
                throw BuildError.packagingFailed("Configuration must be Debug or Release.")
            }
            project.configuration = configuration
        }
        if projects.project(with: project.id) == nil { projects.upsert(project) }
        var snapshot = settings.settings
        if let output = request.outputDirectory {
            guard output.hasPrefix("/") else { throw BuildError.packagingFailed("Output directory must be absolute.") }
            snapshot.outputURL = URL(fileURLWithPath: output, isDirectory: true)
        }
        // Isolate artifacts, including latest.ipa, across projects AND requests.
        // A later build must never overwrite the artifact referenced by a job.
        snapshot.outputURL = snapshot.outputURL
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
            .appendingPathComponent(request.id.uuidString, isDirectory: true)
        // Automatic cleanup may not invalidate another job's artifact receipt.
        snapshot.autoCleanOldBuilds = false
        return (project, snapshot)
    }

    private func runQueuedBuild(_ job: QueuedBuild) {
        guard let project = job.project, let snapshot = job.settings, !engine.isBuilding else {
            buildQueue.complete(state: "failed", error: "Build engine unavailable or invalid saved job.")
            return
        }
        if job.request.clean == true { cleanBuildFolder(for: project) }
        engine.onCompletion = { [weak self] status, record, error in
            guard let self else { return }
            Task { @MainActor in
                var installation: String?
                if status == .success, job.request.installOnDevice == true, let path = record?.appPath {
                    await self.devices.refresh()
                    if case .connectedDevice(let id, _)? = self.devices.devices.first {
                        do {
                            try await self.devices.install(appPath: path, deviceId: id)
                            installation = "installed"
                        } catch { installation = "Install failed: \(error.localizedDescription)" }
                    } else { installation = "No connected device; install manually." }
                }
                self.buildQueue.complete(state: status == .success ? "succeeded" : status.rawValue,
                    artifactPath: record?.outputURL.path, error: error, installResult: installation)
            }
        }
        engine.startBuild(project: project, settings: snapshot, history: history, projectStore: projects)
    }

    var selectedProject: Project? {
        guard let id = selectedProjectId else { return nil }
        return projects.project(with: id)
    }

    // MARK: - Signing health

    /// Soonest-expiring signing asset (provisioning profile or certificate),
    /// used to warn on the dashboard about the free-Apple-ID 7-day treadmill.
    var signingHealth: SigningHealth {
        var items: [(name: String, date: Date)] = []
        for p in profiles.profiles { if let d = p.expirationDate { items.append((p.name, d)) } }
        for c in certificates.identities { if let d = c.expirationDate { items.append((c.name, d)) } }
        guard let soonest = items.min(by: { $0.date < $1.date }) else {
            return SigningHealth(level: .unknown, name: nil, expirationDate: nil, daysRemaining: nil)
        }
        let days = Calendar.current.dateComponents([.day], from: .now, to: soonest.date).day ?? 0
        let level: SigningHealth.Level
        if soonest.date < .now {
            level = .expired
        } else if days <= 3 {
            level = .expiringSoon
        } else {
            level = .ok
        }
        return SigningHealth(level: level, name: soonest.name, expirationDate: soonest.date, daysRemaining: days)
    }

    /// Refreshes the signing stores so `signingHealth` is current.
    func refreshSigning() async {
        await profiles.refresh()
        await certificates.refresh()
    }

    // MARK: - Update check

    /// Checks GitHub Releases for a newer version and populates
    /// `availableUpdate` if there is one. `force: true` (an explicit "Check
    /// Now" click) bypasses both the auto-check setting and a previously
    /// skipped version; the silent launch-time check respects both.
    @discardableResult
    func checkForUpdates(force: Bool = false) async -> AvailableUpdate? {
        guard force || settings.settings.checkForUpdatesAutomatically else { return nil }
        guard let update = await UpdateCheckService.checkForUpdate(currentVersion: AppVersion.version) else { return nil }
        guard force || update.version != settings.settings.skippedUpdateVersion else { return nil }
        availableUpdate = update
        return update
    }

    /// Remembers the given version so it's never shown again (until a newer one ships).
    func skipUpdate(_ version: String) {
        settings.settings.skippedUpdateVersion = version
        availableUpdate = nil
    }

    // MARK: - Projects

    /// Adds a project from a chosen `.xcodeproj`/`.xcworkspace`/`Package.swift`
    /// or a folder containing one. Returns nil if nothing buildable is found.
    @discardableResult
    func addProject(from url: URL) -> Project? {
        guard let resolved = Self.resolveProjectLocation(url) else { return nil }
        var project = Project(
            name: resolved.name,
            path: resolved.path,
            isWorkspace: resolved.kind == .xcworkspace
        )
        project.kindRaw = resolved.kind.rawValue
        if resolved.kind == .swiftPackage {
            // We build packages for macOS and default to a DMG.
            project.detectedPlatform = .macOS
            project.exportFormat = .dmg
            project.destination = .macOS
        }
        projects.upsert(project)
        selectedProjectId = project.id
        return project
    }

    /// Resolves a user-picked URL to a concrete buildable location and its kind.
    /// Accepts a project/workspace bundle, a `Package.swift`, or a folder that
    /// contains any of those.
    static func resolveProjectLocation(_ url: URL) -> (kind: ProjectKind, path: String, name: String)? {
        let fm = FileManager.default
        switch url.pathExtension.lowercased() {
        case "xcworkspace":
            return (.xcworkspace, url.path, url.deletingPathExtension().lastPathComponent)
        case "xcodeproj":
            return (.xcodeproj, url.path, url.deletingPathExtension().lastPathComponent)
        default:
            break
        }
        if url.lastPathComponent == "Package.swift" {
            let dir = url.deletingLastPathComponent()
            return (.swiftPackage, dir.path, dir.lastPathComponent)
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            return (.swiftPackage, url.path, url.lastPathComponent)
        }
        let contents = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        if let ws = contents.first(where: { $0.pathExtension.lowercased() == "xcworkspace" }) {
            return (.xcworkspace, ws.path, ws.deletingPathExtension().lastPathComponent)
        }
        if let proj = contents.first(where: { $0.pathExtension.lowercased() == "xcodeproj" }) {
            return (.xcodeproj, proj.path, proj.deletingPathExtension().lastPathComponent)
        }
        return nil
    }

    func deleteProject(_ project: Project) {
        projects.remove(project)
        if selectedProjectId == project.id { selectedProjectId = nil }
    }

    /// Deletes the app-managed DerivedData for a project ("Clean Build Folder").
    func cleanBuildFolder(for project: Project) {
        try? FileManager.default.removeItem(at: AppPaths.derivedData(for: project))
    }

    /// Clean build folder, then build from scratch.
    func rebuild(projectId: UUID) {
        guard let project = projects.project(with: projectId) else { return }
        submitBuild(project: project, clean: true)
    }

    /// Installs the latest successful build onto the first connected device,
    /// reporting the outcome via a notification (used from the menu bar panel,
    /// where there's no room for a device-picker UI).
    func installLatestOnFirstDevice() {
        Task {
            await devices.refresh()
            guard case .connectedDevice(let id, let name)? = devices.devices.first else {
                NotificationService.post(
                    title: "No device connected",
                    body: "Connect your iPhone via USB or Wi-Fi and trust this Mac."
                )
                return
            }
            let message = await installLatestBuildOnDevice(deviceId: id)
            NotificationService.post(title: name, body: message)
        }
    }

    // MARK: - Devices

    /// Installs the most recent successful build's `.app` onto a connected device.
    /// Returns a user-facing result message.
    @discardableResult
    func installLatestBuildOnDevice(deviceId: String) async -> String {
        guard let build = history.mostRecentSuccess, let appPath = build.appPath,
              FileManager.default.fileExists(atPath: appPath)
        else {
            return "No built app available. Build a project first."
        }
        do {
            try await devices.install(appPath: appPath, deviceId: deviceId)
            return "Installed \(build.projectName) on device."
        } catch {
            return "Install failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Build history

    /// Prunes build history to the configured retention count and deletes
    /// stale versioned IPAs for every project represented in history.
    func cleanOldBuilds() {
        history.prune(to: settings.settings.keepBuildHistoryCount)
        let projectNames = Set(history.builds.map(\.projectName))
        for name in projectNames {
            AutoClean.runNow(settings: settings.settings, projectName: name)
        }
    }

    // MARK: - Scheduler

    func applySchedulerSettings() async {
        guard settings.settings.scheduledBuildsEnabled,
              let id = settings.settings.scheduledProjectId,
              let project = projects.project(with: id)
        else {
            try? await SchedulerService.disable()
            return
        }
        do {
            try await SchedulerService.enable(project: project, settings: settings.settings)
        } catch {
            // Surface in UI via the automation view's error binding is handled there.
        }
    }
}
