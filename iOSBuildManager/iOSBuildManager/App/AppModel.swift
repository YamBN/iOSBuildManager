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

    let settings: SettingsStore
    let projects: ProjectStore
    let history: BuildHistoryStore
    let devices: DeviceStore
    let engine: BuildEngine
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

        // Migrate LaunchAgents installed under old bundle identifiers; if one
        // existed and scheduling is still on, re-install it under the current
        // identifier so scheduled builds keep working after the rename.
        Task { [weak self] in
            let hadLegacy = await SchedulerService.removeLegacyAgents()
            if hadLegacy { await self?.applySchedulerSettings() }
        }
    }

    // MARK: - Build

    func startBuild(for projectId: UUID) {
        guard let project = projects.project(with: projectId) else { return }
        engine.startBuild(
            project: project,
            settings: settings.settings,
            history: history,
            projectStore: projects
        )
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
        cleanBuildFolder(for: project)
        startBuild(for: project.id)
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
