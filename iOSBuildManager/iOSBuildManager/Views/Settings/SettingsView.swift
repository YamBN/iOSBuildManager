import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Enables only Xcode project/workspace bundles (and plain folders, so the
/// user can navigate) in the "Add Project" open panel.
final class ProjectOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate, @unchecked Sendable {
    static let shared = ProjectOpenPanelDelegate()

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "xcodeproj" || ext == "xcworkspace" { return true }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case build = "Build"
    case signing = "Signing"
    case distribution = "Distribution"
    case advanced = "Advanced"

    var id: String { rawValue }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var model: AppModel

    @State private var tab: SettingsTab = .general

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header
                tabPicker

                switch tab {
                case .general: GeneralSettingsTab()
                case .build: BuildSettingsTab()
                case .signing: SigningSettingsTab()
                case .distribution: DistributionSettingsTab()
                case .advanced: AdvancedSettingsTab()
                }
            }
            .padding(20)
        }
        .navigationTitle("Settings")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.largeTitle.weight(.bold))
            Text("Everything is stored locally in Application Support. No analytics, no tracking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            ForEach(SettingsTab.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var schemes: [String] = []
    @State private var detectingSchemes = false
    @State private var schemeError: String?
    @State private var helperInstalled = false

    private var project: Project? { model.selectedProject ?? projects.projects.first }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            projectCard
            outputRow
            toggleRow
        }
        .onAppear {
            if model.selectedProjectId == nil { model.selectedProjectId = projects.projects.first?.id }
            helperInstalled = FileManager.default.fileExists(atPath: AppPaths.helperScriptURL.path)
        }
        .task(id: project?.id) { await loadSchemes() }
    }

    private var projectCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Project", systemImage: "folder")

                HStack(spacing: 8) {
                    Text("Project Path").font(.subheadline.weight(.medium)).frame(width: 110, alignment: .leading)
                    if projects.projects.isEmpty {
                        Text("No project added").foregroundStyle(.secondary)
                    } else {
                        Picker("", selection: Binding(
                            get: { model.selectedProjectId ?? projects.projects.first?.id },
                            set: { model.selectedProjectId = $0 }
                        )) {
                            ForEach(projects.projects) { p in
                                Text(p.path).tag(Optional(p.id))
                            }
                        }
                        .labelsHidden()
                    }
                    Spacer()
                    Button("Choose…") { showOpenPanel() }
                    if let project {
                        Button(role: .destructive) { model.deleteProject(project) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }

                if let project {
                    Divider()

                    HStack(spacing: 8) {
                        Text("Scheme").font(.subheadline.weight(.medium)).frame(width: 110, alignment: .leading)
                        if schemes.isEmpty && !detectingSchemes {
                            Text("No schemes detected").foregroundStyle(.secondary)
                        } else {
                            Picker("", selection: schemeBinding) {
                                ForEach(schemes, id: \.self) { Text($0).tag($0 as String?) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 260)
                        }
                        Spacer()
                        Button {
                            Task { await loadSchemes(force: true) }
                        } label: {
                            if detectingSchemes {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(detectingSchemes)
                    }
                    if let schemeError {
                        Text(schemeError).font(.caption).foregroundStyle(.red)
                    }

                    HStack(spacing: 8) {
                        Text("Configuration").font(.subheadline.weight(.medium)).frame(width: 110, alignment: .leading)
                        Picker("", selection: configurationBinding) {
                            ForEach(BuildConfiguration.allCases) { config in
                                Text(config.displayName).tag(config)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Button {
                            model.startBuild(for: project.id)
                            model.selection = .logs
                        } label: {
                            Label("Build & Package IPA", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(project.selectedScheme == nil)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var outputRow: some View {
        GlassPanel {
            HStack(spacing: 8) {
                Text("Output Directory").font(.subheadline.weight(.medium)).frame(width: 130, alignment: .leading)
                Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
                Text(settings.settings.outputURL.path)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button("Choose…") { chooseFolder() }
            }
        }
    }

    private var toggleRow: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Auto Clean Old Builds", isOn: Binding(
                    get: { settings.settings.autoCleanOldBuilds },
                    set: { settings.settings.autoCleanOldBuilds = $0 }
                ))
                Toggle("Auto Build After Xcode Build", isOn: Binding(
                    get: { helperInstalled },
                    set: { newValue in
                        helperInstalled = newValue
                        if newValue {
                            try? ScriptGenerator.installHelperScript()
                        } else {
                            try? FileManager.default.removeItem(at: AppPaths.helperScriptURL)
                        }
                    }
                ))
                Text("Automatically create an IPA after a successful build. Requires the Run Script Phase from the Advanced tab.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("Upload latest.ipa to iCloud", isOn: Binding(
                    get: { settings.settings.keepLatestIPA },
                    set: { settings.settings.keepLatestIPA = $0 }
                ))
                Text("Keep latest.ipa synced whenever a new build succeeds.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("Notify When Build Completes", isOn: Binding(
                    get: { settings.settings.notifyOnBuildComplete },
                    set: { settings.settings.notifyOnBuildComplete = $0 }
                ))
                Text("Show a macOS notification when a build succeeds or fails.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("Show Menu Bar Icon", isOn: Binding(
                    get: { settings.settings.showMenuBarIcon },
                    set: { settings.settings.showMenuBarIcon = $0 }
                ))
                Text("Quick actions stay available from the menu bar; the app keeps running in the background when the window is closed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var schemeBinding: Binding<String?> {
        Binding(
            get: { project?.selectedScheme },
            set: { newValue in if let id = project?.id { projects.update(id) { $0.selectedScheme = newValue } } }
        )
    }

    private var configurationBinding: Binding<BuildConfiguration> {
        Binding(
            get: { project?.configuration ?? .release },
            set: { newValue in if let id = project?.id { projects.update(id) { $0.configuration = newValue } } }
        )
    }

    private func loadSchemes(force: Bool = false) async {
        guard let project, (schemes.isEmpty || force) else { return }
        detectingSchemes = true
        schemeError = nil
        defer { detectingSchemes = false }
        do {
            let detected = try await XcodeBuildService.schemes(for: project)
            schemes = detected
            if detected.count == 1, project.selectedScheme == nil {
                projects.update(project.id) { $0.selectedScheme = detected.first }
            }
            if detected.isEmpty {
                schemeError = "No schemes found. Open the project in Xcode and let it resolve schemes."
            }
        } catch {
            schemeError = error.localizedDescription
            schemes = []
        }
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        // .xcodeproj/.xcworkspace are folder packages whose UTIs come from
        // Xcode's declarations; UTType(filenameExtension:) resolves to a dynamic
        // type that doesn't match them, graying everything out. Filter by
        // extension via the delegate instead.
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.delegate = ProjectOpenPanelDelegate.shared
        panel.message = "Choose an .xcodeproj or .xcworkspace"
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            let project = model.addProject(from: url)
            model.selectedProjectId = project.id
            schemes = []
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Output Folder"
        if panel.runModal() == .OK, let url = panel.url {
            settings.settings.outputURL = url
        }
    }
}

// MARK: - Build

private struct BuildSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var devices: DeviceStore

    private var project: Project? { model.selectedProject ?? projects.projects.first }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Destination", systemImage: "iphone")
                    if let project {
                        Picker("Destination", selection: destinationBinding(for: project)) {
                            ForEach(devices.allDestinations) { dest in
                                Label(dest.displayName, systemImage: dest.systemImage).tag(dest)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()

                        HStack {
                            Text("\(devices.devices.count) connected device(s) detected.")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                Task { await devices.refresh() }
                            } label: {
                                if devices.isRefreshing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    } else {
                        Text("Add a project in the General tab first.").foregroundStyle(.secondary)
                    }
                }
            }

            if let project {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Output Naming", systemImage: "textformat")
                        Text("Versioned builds are written as:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(project.name.replacingOccurrences(of: " ", with: "_"))-1.0.0-1.ipa")
                            .font(.system(.callout, design: .monospaced))
                        Text("latest.ipa is refreshed alongside it when enabled in General.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task { await devices.refresh() }
    }

    private func destinationBinding(for project: Project) -> Binding<BuildDestination> {
        Binding(
            get: { project.destination },
            set: { newValue in projects.update(project.id) { $0.destination = newValue } }
        )
    }
}

// MARK: - Signing

private struct SigningSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var profiles: ProvisioningProfileStore
    @EnvironmentObject private var certificates: CertificateStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Team", systemImage: "person.crop.circle")
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profiles.primaryTeamName ?? "No Team Detected")
                                .font(.title3.weight(.semibold))
                            if let teamId = profiles.primaryTeamId {
                                Text("Team ID: \(teamId)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Manage Profiles") { model.selection = .profiles }
                            .buttonStyle(.bordered)
                    }
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Code Signing Identity", systemImage: "checkmark.seal")
                    if let identity = certificates.identities.first {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(identity.name).font(.callout.weight(.medium))
                                Text(identity.statusLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Manage Certificates") { model.selection = .certificates }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        Text("No signing identity found. Sign in with your Apple ID in Xcode → Settings → Accounts, or import a certificate.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Manage Certificates") { model.selection = .certificates }
                            .buttonStyle(.bordered)
                    }
                }
            }

            Text("Code signing itself is configured per-target in Xcode (Signing & Capabilities). This app builds and packages whatever Xcode signs — it never bypasses Apple's code signing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            await profiles.refresh()
            await certificates.refresh()
        }
    }
}

// MARK: - Distribution

private struct DistributionSettingsTab: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Output", systemImage: "externaldrive.fill")

                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
                        Text(settings.settings.outputURL.path)
                            .font(.callout)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                    }
                    .padding(10)
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: 10) {
                        Button { chooseFolder() } label: { Label("Choose…", systemImage: "folder.badge.plus") }
                        Button { FinderActions.openFolder(settings.settings.outputURL) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                        Button { FinderActions.copyPath(settings.settings.outputURL) } label: { Label("Copy Path", systemImage: "doc.on.doc") }
                    }
                    .buttonStyle(.bordered)

                    Toggle("Validate iCloud Drive output folder", isOn: Binding(
                        get: { settings.settings.validateICloudOutput },
                        set: { settings.settings.validateICloudOutput = $0 }
                    ))

                    if let warning = settings.validateOutput() {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Build History", systemImage: "clock.arrow.circlepath")
                    HStack {
                        Text("Keep last")
                        Stepper("\(settings.settings.keepBuildHistoryCount) builds",
                                value: Binding(
                                    get: { settings.settings.keepBuildHistoryCount },
                                    set: { settings.settings.keepBuildHistoryCount = max(1, $0) }
                                ),
                                in: 1...200)
                        Spacer()
                    }
                    Text("Older versioned IPAs for a project are deleted beyond this count; latest.ipa is always kept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Output Folder"
        if panel.runModal() == .OK, let url = panel.url {
            settings.settings.outputURL = url
        }
    }
}

// MARK: - Advanced

private struct AdvancedSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var projects: ProjectStore

    @State private var helperInstalled = false
    @State private var schedulerMessage: String?
    @State private var isApplying = false

    private var runScript: String { ScriptGenerator.runScriptPhase() }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            runScriptCard
            schedulingCard
            appearanceCard
            aboutCard
        }
        .onAppear { helperInstalled = FileManager.default.fileExists(atPath: AppPaths.helperScriptURL.path) }
    }

    private var runScriptCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Xcode Run Script Phase", systemImage: "curlybraces")

                Text("Paste this into your target's Build Phases as a New Run Script Phase. It only packages the already-built app for device builds — it never calls xcodebuild again, so there are no build loops.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(runScript)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .padding(12)
                .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 10) {
                    Button { copy(runScript) } label: {
                        Label("Copy Script", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        do {
                            _ = try ScriptGenerator.installHelperScript()
                            helperInstalled = true
                            schedulerMessage = "Helper script installed to Application Support."
                        } catch {
                            schedulerMessage = "Failed: \(error.localizedDescription)"
                        }
                    } label: {
                        Label(helperInstalled ? "Reinstall Helper" : "Install Helper Script", systemImage: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.bordered)
                }

                steps
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How to add it in Xcode:").font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                step("1", "Open your project → select the app Target.")
                step("2", "Go to Build Phases → + → New Run Script Phase.")
                step("3", "Paste the script above into the script body.")
                step("4", "Ensure \"Run script only when installing\" is OFF.")
                step("5", "Build for a device — latest.ipa appears in iCloud Builds.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n)
                .font(.caption.weight(.bold))
                .frame(width: 18, height: 18)
                .background(Color.accentColor.opacity(0.18), in: Circle())
            Text(text)
        }
    }

    private var schedulingCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Scheduled Builds", systemImage: "clock.badge.checkmark")

                Text("Installs a LaunchAgent that rebuilds and repackages on a schedule — even when the app is closed. Recommended for free provisioning: within the 7-day signing window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("Enable scheduled builds", isOn: Binding(
                    get: { settings.settings.scheduledBuildsEnabled },
                    set: { settings.settings.scheduledBuildsEnabled = $0 }
                ))

                if settings.settings.scheduledBuildsEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project").font(.subheadline.weight(.medium))
                        Picker("Project", selection: Binding(
                            get: { settings.settings.scheduledProjectId },
                            set: { settings.settings.scheduledProjectId = $0 }
                        )) {
                            Text("Choose…").tag(UUID?.none)
                            ForEach(projects.projects) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 260)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Frequency").font(.subheadline.weight(.medium))
                        Picker("Frequency", selection: Binding(
                            get: { settings.settings.scheduleFrequency },
                            set: { settings.settings.scheduleFrequency = $0 }
                        )) {
                            ForEach(ScheduleFrequency.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                    }

                    frequencyControls

                    Text(SchedulerService.summary(for: settings.settings))
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }

                HStack {
                    Button {
                        Task { await apply() }
                    } label: {
                        if isApplying {
                            HStack { ProgressView().controlSize(.small); Text("Applying…") }
                        } else {
                            Label("Apply & Install LaunchAgent", systemImage: "checkmark.shield")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isApplying || settings.settings.scheduledBuildsEnabled && settings.settings.scheduledProjectId == nil)

                    if SchedulerService.isEnabled {
                        Label("Agent installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }

                if let msg = schedulerMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The controls that change per frequency: interval days, a time picker,
    /// and/or a weekday selector.
    @ViewBuilder
    private var frequencyControls: some View {
        switch settings.settings.scheduleFrequency {
        case .everyNDays:
            HStack {
                Text("Rebuild every").font(.subheadline.weight(.medium))
                Stepper("\(settings.settings.scheduledBuildIntervalDays) day\(settings.settings.scheduledBuildIntervalDays == 1 ? "" : "s")",
                        value: Binding(
                            get: { settings.settings.scheduledBuildIntervalDays },
                            set: { settings.settings.scheduledBuildIntervalDays = max(1, $0) }
                        ),
                        in: 1...30)
                Spacer()
            }

        case .daily:
            HStack(spacing: 10) {
                Text("At").font(.subheadline.weight(.medium))
                DatePicker("", selection: scheduleTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Spacer()
            }

        case .weekly:
            VStack(alignment: .leading, spacing: 10) {
                weekdaySelector
                HStack(spacing: 10) {
                    Text("At").font(.subheadline.weight(.medium))
                    DatePicker("", selection: scheduleTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer()
                }
            }
        }
    }

    private var weekdaySelector: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.all, id: \.self) { day in
                let isOn = settings.settings.scheduleWeekdays.contains(day)
                Button {
                    var days = Set(settings.settings.scheduleWeekdays)
                    if isOn { days.remove(day) } else { days.insert(day) }
                    settings.settings.scheduleWeekdays = days.sorted()
                } label: {
                    Text(Weekday.initial(day))
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.08))
                        )
                        .foregroundStyle(isOn ? .white : .primary)
                }
                .buttonStyle(.plain)
                .help(Weekday.shortName(day))
            }
        }
    }

    /// Bridges the stored hour/minute to a `Date` for the time picker.
    private var scheduleTime: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = settings.settings.scheduleHour
                comps.minute = settings.settings.scheduleMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.settings.scheduleHour = comps.hour ?? 3
                settings.settings.scheduleMinute = comps.minute ?? 0
            }
        )
    }

    private var appearanceCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Appearance", systemImage: "paintbrush")
                Picker("Theme", selection: Binding(
                    get: { settings.settings.theme },
                    set: { settings.settings.theme = $0 }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.displayName, systemImage: theme.systemImage).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var aboutCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "About", systemImage: "info.circle")
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iOS Build Manager").font(.callout.weight(.semibold))
                        Text("Version \(AppVersion.version) (\(AppVersion.buildNumber))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Local • Private")
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)
                    Text("Created by **\(AppVersion.authorName)**")
                        .font(.callout)
                    Link("@\(AppVersion.authorGitHubHandle)", destination: AppVersion.authorGitHubURL)
                        .font(.callout)
                    Spacer()
                    Link(destination: AppVersion.repositoryURL) {
                        Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.caption)
                    }
                }

                Divider()

                Text("What's Included").font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(AppVersion.highlights, id: \.self) { highlight in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                                .frame(width: 16)
                                .padding(.top, 2)
                            Text(highlight)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                Text("Release History").font(.subheadline.weight(.semibold))
                ForEach(AppVersion.changelog) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: entry.type.systemImage)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.version) • \(entry.date)")
                                .font(.caption.weight(.semibold))
                            Text(entry.summary)
                                .font(.callout)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func apply() async {
        isApplying = true
        defer { isApplying = false }
        await model.applySchedulerSettings()
        schedulerMessage = SchedulerService.isEnabled
            ? "LaunchAgent installed at ~/Library/LaunchAgents/\(AppPaths.schedulerIdentifier).plist"
            : "Scheduled builds disabled."
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
