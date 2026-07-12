import Foundation
import SwiftUI

/// Pure, testable logic for turning "how long has this build been running"
/// into a progress estimate — `xcodebuild` doesn't expose a real percentage,
/// so this approximates one from the project's own build history.
enum BuildProgressEstimator {
    /// Fallback estimate used for a project's first build, before there's any
    /// history to average — keeps a moving percentage bar on screen instead of
    /// a bare spinner. It self-corrects once real durations are recorded.
    static let defaultExpectedDuration: Double = 60

    /// Mean of the last few successful build durations, or nil with no history.
    static func expectedDuration(from recentDurations: [Double]) -> Double? {
        guard !recentDurations.isEmpty else { return nil }
        return recentDurations.reduce(0, +) / Double(recentDurations.count)
    }

    /// Progress in 0...1, capped short of 100% since a build isn't done until
    /// it's actually done — the last stretch just sits at the cap instead of
    /// lying about completion. Nil expected duration means "unknown" (caller
    /// should show an indeterminate spinner instead of a percentage).
    static func progress(elapsed: TimeInterval, expected: Double?) -> Double? {
        guard let expected, expected > 0 else { return nil }
        return min(0.95, max(0, elapsed / expected))
    }

    /// "1:05" style elapsed-time label for the UI.
    static func formattedElapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Drives a single build: runs `xcodebuild`, streams logs into `@Published`
/// state, then packages the resulting `.app` into an IPA and records history.
@MainActor
final class BuildEngine: ObservableObject {
    @Published private(set) var status: BuildStatus = .idle
    @Published private(set) var logLines: [String] = []
    @Published private(set) var currentProjectName: String?
    @Published private(set) var lastError: String?
    @Published private(set) var buildStartedAt: Date?
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    /// 0...1 estimate, or nil when there's no build history to estimate from
    /// (shows an indeterminate spinner instead of a percentage).
    @Published private(set) var estimatedProgress: Double?

    private var process: Process?
    private var consumerTask: Task<Void, Never>?
    private var progressTicker: Task<Void, Never>?
    private var channel: EagerLineChannel?
    private var exitBox: ExitCodeBox?
    private var isCancelling = false
    private var expectedDuration: Double?

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
        elapsedSeconds = 0

        let recentDurations = history.builds
            .filter { $0.projectId == project.id && $0.status == .success }
            .prefix(5)
            .map(\.durationSeconds)
        expectedDuration = BuildProgressEstimator.expectedDuration(from: Array(recentDurations))
            ?? BuildProgressEstimator.defaultExpectedDuration
        estimatedProgress = BuildProgressEstimator.progress(elapsed: 0, expected: expectedDuration)
        startProgressTicker()

        let channel = EagerLineChannel()
        let box = ExitCodeBox()
        self.channel = channel
        self.exitBox = box

        let invocation = Self.buildInvocation(for: project)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: invocation.executable)
        proc.arguments = invocation.arguments
        proc.currentDirectoryURL = invocation.cwd

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
        elapsedSeconds = 0
        estimatedProgress = nil
    }

    /// The command, arguments, and working directory used to build a project —
    /// `xcodebuild` for Xcode projects/workspaces, `swift build` for packages.
    static func buildInvocation(for project: Project) -> (executable: String, arguments: [String], cwd: URL) {
        if project.kind == .swiftPackage {
            return (SwiftPackageService.swiftPath,
                    SwiftPackageService.buildArguments(product: project.selectedScheme, configuration: project.configuration),
                    project.workingDirectory)
        }
        return (XcodeBuildService.xcodebuildPath,
                XcodeBuildService.buildArguments(for: project),
                project.workingDirectory)
    }

    private func buildCommandSummary(for project: Project) -> String {
        let invocation = Self.buildInvocation(for: project)
        return (invocation.executable as NSString).lastPathComponent + " " + invocation.arguments.joined(separator: " ")
    }

    /// Ticks elapsed time + the derived progress estimate every half second
    /// while a build is running.
    private func startProgressTicker() {
        progressTicker?.cancel()
        progressTicker = Task { [weak self] in
            while let self, !Task.isCancelled, self.isBuilding {
                if let startedAt = self.buildStartedAt {
                    let elapsed = Date().timeIntervalSince(startedAt)
                    self.elapsedSeconds = elapsed
                    self.estimatedProgress = BuildProgressEstimator.progress(elapsed: elapsed, expected: self.expectedDuration)
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func stopProgressTicker() {
        progressTicker?.cancel()
        progressTicker = nil
    }

    private func finalize(exitCode: Int32) async {
        let startedAt = buildStartedAt ?? .now
        let duration = Date().timeIntervalSince(startedAt)
        stopProgressTicker()
        estimatedProgress = 1
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
            let appURL: URL
            if project.isSwiftPackage {
                appURL = try await locatePackageApp(project: project)
                logLines.append("▸ Wrapped executable into app bundle: \(appURL.path)")
            } else {
                appURL = try XcodeBuildService.locateApp(for: project)
            }
            let info = try XcodeBuildService.readAppInfo(at: appURL)
            let appName = appURL.deletingPathExtension().lastPathComponent

            logLines.append("▸ Found app: \(appURL.path)")

            // Verify the code signature before packaging so nobody discovers a
            // broken artifact at install time. Unsigned is only a warning; the
            // guidance differs by platform.
            if case .genericIOSSimulator = project.destination {
                logLines.append("▸ Simulator build — skipping signature check (not installable on device).")
            } else if let authority = await XcodeBuildService.codesignAuthority(at: appURL) {
                logLines.append("▸ Code signature: \(authority)")
            } else if project.isMac {
                logLines.append("▸ ⚠️ App is NOT code-signed. Gatekeeper will block it on other Macs until it's signed/notarized, or opened via System Settings → Privacy & Security. To sign: open the project in Xcode → Signing & Capabilities → set a Team.")
            } else {
                logLines.append("▸ ⚠️ App is NOT code-signed. SideStore/AltStore will re-sign it, but direct device install will fail. To sign: open the project in Xcode → Signing & Capabilities → set a Team.")
            }

            let outputURL: URL
            if project.isMac {
                let format = project.resolvedExportFormat
                logLines.append("▸ Packaging \(format.displayName)…")
                outputURL = try await MacPackager.export(
                    format: format,
                    appURL: appURL,
                    appName: appName,
                    version: info.version,
                    buildNumber: info.buildNumber,
                    outputFolder: settings.outputURL,
                    keepLatest: settings.keepLatestIPA
                )
            } else {
                logLines.append("▸ Packaging IPA…")
                outputURL = try await IPAPackager.pack(
                    appURL: appURL,
                    appName: appName,
                    version: info.version,
                    buildNumber: info.buildNumber,
                    outputFolder: settings.outputURL,
                    keepLatest: settings.keepLatestIPA
                )
            }

            let size = IPAPackager.fileSize(at: outputURL)
            logLines.append("▸ Ready: \(outputURL.path) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))")

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
                outputURL: outputURL,
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

    /// Locates the executable produced by `swift build` and wraps it in a
    /// minimal `.app` so the rest of the pipeline (signing check, packaging)
    /// can treat it like any other Mac app.
    private func locatePackageApp(project: Project) async throws -> URL {
        let binPath = try await SwiftPackageService.binPath(
            packageDir: project.workingDirectory,
            configuration: project.configuration
        )
        let product = project.selectedScheme ?? project.name
        let executable = binPath.appendingPathComponent(product)
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw BuildError.packagingFailed("Built executable '\(product)' not found at \(executable.path). Pick the correct product in Settings.")
        }
        let container = project.workingDirectory.appendingPathComponent(".build/packaged", isDirectory: true)
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let bundleId = "com.iosbuildmanager." + product.lowercased().replacingOccurrences(of: " ", with: "-")
        return try SwiftPackageService.wrapExecutableInApp(
            executableURL: executable,
            appName: product,
            bundleIdentifier: bundleId,
            version: "1.0",
            buildNumber: "1",
            containerDir: container
        )
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
