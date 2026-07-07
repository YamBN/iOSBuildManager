import Foundation
import SwiftUI

/// The single source of truth for app-wide state. Owns all stores and the
/// build engine, and exposes high-level actions used by views.
@MainActor
final class AppModel: ObservableObject {
    @Published var selection: SidebarSection = .dashboard
    @Published var selectedProjectId: UUID?

    let settings: SettingsStore
    let projects: ProjectStore
    let history: BuildHistoryStore
    let devices: DeviceStore
    let engine: BuildEngine
    let profiles: ProvisioningProfileStore
    let certificates: CertificateStore

    init() {
        AppPaths.ensureDirectories()
        self.settings = SettingsStore()
        self.projects = ProjectStore()
        self.history = BuildHistoryStore()
        self.devices = DeviceStore()
        self.engine = BuildEngine()
        self.profiles = ProvisioningProfileStore()
        self.certificates = CertificateStore()
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

    // MARK: - Projects

    func addProject(from url: URL) -> Project {
        let name = url.deletingPathExtension().lastPathComponent
        let project = Project(
            name: name,
            path: url.path,
            isWorkspace: Project.isWorkspacePath(url.path)
        )
        projects.upsert(project)
        selectedProjectId = project.id
        return project
    }

    func deleteProject(_ project: Project) {
        projects.remove(project)
        if selectedProjectId == project.id { selectedProjectId = nil }
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
