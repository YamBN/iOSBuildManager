import Foundation
import SwiftUI

/// Drives a single build: runs `xcodebuild`, streams logs into `@Published`
/// state, then packages the resulting `.app` into an IPA and records history.
@MainActor
final class BuildEngine: ObservableObject {
    @Published private(set) var status: BuildStatus = .idle
    @Published private(set) var logLines: [String] = []
    @Published private(set) var currentProjectName: String?
    @Published private(set) var lastError: String?
    @Published private(set) var buildStartedAt: Date?

    private var process: Process?
    private var consumerTask: Task<Void, Never>?
    private var channel: EagerLineChannel?
    private var exitBox: ExitCodeBox?
    private var isCancelling = false

    private weak var history: BuildHistoryStore?
    private weak var projectStore: ProjectStore?
    private var currentProject: Project?
    private var currentSettings: AppSettings?

    var isBuilding: Bool { status == .building }

    func startBuild(
        project: Project,
        settings: AppSettings,
        history: BuildHistoryStore,
        projectStore: ProjectStore
    ) {
        guard !isBuilding else { return }
        AppPaths.ensureDirectories()

        self.history = history
        self.projectStore = projectStore
        self.currentProject = project
        self.currentSettings = settings
        self.isCancelling = false

        status = .building
        currentProjectName = project.name
        lastError = nil
        logLines = ["▸ \(buildCommandSummary(for: project))"]
        buildStartedAt = .now

        let channel = EagerLineChannel()
        let box = ExitCodeBox()
        self.channel = channel
        self.exitBox = box

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: XcodeBuildService.xcodebuildPath)
        proc.arguments = XcodeBuildService.buildArguments(for: project)
        proc.currentDirectoryURL = project.fileURL.deletingLastPathComponent()

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        let handle = pipe.fileHandleForReading
        let lineBuffer = LineBuffer()
        handle.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            for line in lineBuffer.append(data) {
                channel.yield(line)
            }
        }
        proc.terminationHandler = { p in
            box.set(p.terminationStatus)
            channel.finish()
        }

        do {
            try proc.run()
            process = proc
        } catch {
            handle.readabilityHandler = nil
            lastError = error.localizedDescription
            status = .failed
            channel.finish()
            return
        }

        consumerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await line in channel.stream {
                self.logLines.append(line)
            }
            await self.finalize(exitCode: box.value)
        }
    }

    func cancel() {
        guard isBuilding else { return }
        isCancelling = true
        process?.terminate()
    }

    func reset() {
        guard !isBuilding else { return }
        status = .idle
        lastError = nil
        currentProjectName = nil
        logLines.removeAll()
        buildStartedAt = nil
    }

    private func buildCommandSummary(for project: Project) -> String {
        let args = XcodeBuildService.buildArguments(for: project)
        return "xcodebuild " + args.joined(separator: " ")
    }

    private func finalize(exitCode: Int32) async {
        let startedAt = buildStartedAt ?? .now
        let duration = Date().timeIntervalSince(startedAt)
        defer {
            process = nil
            channel = nil
            exitBox = nil
            consumerTask = nil
        }

        guard let project = currentProject, let settings = currentSettings else {
            status = .idle
            return
        }

        if isCancelling {
            status = .cancelled
            logLines.append("▸ Build cancelled.")
            return
        }

        if exitCode != 0 {
            let err = BuildError.processFailed(command: "xcodebuild", exitCode: exitCode)
            lastError = err.localizedDescription
            logLines.append("▸ \(err.localizedDescription)")
            recordFailure(project: project, duration: duration)
            status = .failed
            notifyIfEnabled(settings: settings, projectName: project.name, success: false, detail: err.localizedDescription)
            return
        }

        do {
            let appURL = try XcodeBuildService.locateApp(for: project)
            let info = try XcodeBuildService.readAppInfo(at: appURL)
            let appName = appURL.deletingPathExtension().lastPathComponent

            logLines.append("▸ Found app: \(appURL.path)")

            // Verify the code signature before packaging so nobody discovers a
            // broken IPA at install time. Unsigned is only a warning: SideStore
            // and AltStore re-sign IPAs with the user's Apple ID.
            if case .genericIOSSimulator = project.destination {
                logLines.append("▸ Simulator build — skipping signature check (not installable on device).")
            } else if let authority = await XcodeBuildService.codesignAuthority(at: appURL) {
                logLines.append("▸ Code signature: \(authority)")
            } else {
                logLines.append("▸ ⚠️ App is NOT code-signed. SideStore/AltStore will re-sign it, but direct device install will fail. To sign: open the project in Xcode → Signing & Capabilities → set a Team.")
            }

            logLines.append("▸ Packaging IPA…")

            let ipaURL = try await IPAPackager.pack(
                appURL: appURL,
                appName: appName,
                version: info.version,
                buildNumber: info.buildNumber,
                outputFolder: settings.outputURL,
                keepLatest: settings.keepLatestIPA
            )

            let size = IPAPackager.fileSize(at: ipaURL)
            logLines.append("▸ IPA ready: \(ipaURL.path) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))")

            let record = BuildRecord(
                projectId: project.id,
                projectName: project.name,
                scheme: project.selectedScheme ?? "",
                configuration: project.configuration.rawValue,
                version: info.version,
                buildNumber: info.buildNumber,
                date: .now,
                sizeBytes: size,
                status: .success,
                outputURL: ipaURL,
                appPath: appURL.path,
                durationSeconds: duration,
                log: logLines.joined(separator: "\n")
            )
            history?.add(record)
            if settings.autoCleanOldBuilds {
                history?.prune(to: settings.keepBuildHistoryCount)
                AutoClean.run(settings: settings, projectName: project.name)
            }
            projectStore?.markBuilt(projectId: project.id)
            status = .success
            notifyIfEnabled(
                settings: settings,
                projectName: project.name,
                success: true,
                detail: "\(info.version) (\(info.buildNumber)) • \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
            )
        } catch {
            lastError = error.localizedDescription
            logLines.append("▸ ERROR: \(error.localizedDescription)")
            recordFailure(project: project, duration: duration)
            status = .failed
            notifyIfEnabled(settings: settings, projectName: project.name, success: false, detail: error.localizedDescription)
        }
    }

    private func notifyIfEnabled(settings: AppSettings, projectName: String, success: Bool, detail: String) {
        guard settings.notifyOnBuildComplete else { return }
        NotificationService.buildFinished(projectName: projectName, success: success, detail: detail)
    }

    private func recordFailure(project: Project, duration: Double) {
        let record = BuildRecord(
            projectId: project.id,
            projectName: project.name,
            scheme: project.selectedScheme ?? "",
            configuration: project.configuration.rawValue,
            version: "—",
            buildNumber: "—",
            date: .now,
            sizeBytes: 0,
            status: .failed,
            outputURL: settingsFailureURL(project: project),
            appPath: nil,
            durationSeconds: duration,
            log: logLines.joined(separator: "\n")
        )
        history?.add(record)
        if let settings = currentSettings {
            history?.prune(to: settings.keepBuildHistoryCount)
        }
    }

    private func settingsFailureURL(project: Project) -> URL {
        (currentSettings?.outputURL ?? AppPaths.defaultOutputURL)
            .appendingPathComponent("\(project.name)-failed.ipa")
    }
}
