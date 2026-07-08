import AppKit
import SwiftUI

/// The custom menu bar panel (MenuBarExtra `.window` style): current project
/// with inline configuration/destination pickers, primary build actions with
/// shortcut hints, recent builds, and app controls.
struct MenuBarMenu: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var engine: BuildEngine
    @EnvironmentObject private var history: BuildHistoryStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var devices: DeviceStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    private var project: Project? {
        model.selectedProject ?? projects.projects.first
    }

    private var latest: BuildRecord? { history.mostRecentSuccess }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel("Current Project")

            projectRow
                .padding(.bottom, 4)

            divider

            PanelRow(icon: "play.fill", title: "Build and Create IPA", shortcut: "⌘B") {
                if let project {
                    model.startBuild(for: project.id)
                }
                closePanel()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(project == nil || engine.isBuilding)

            PanelRow(icon: "arrow.clockwise", title: "Rebuild", shortcut: "⇧⌘B") {
                if let project {
                    model.rebuild(projectId: project.id)
                }
                closePanel()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(project == nil || engine.isBuilding)

            PanelRow(icon: "trash", title: "Clean Build Folder", shortcut: "⌥⌘K") {
                if let project {
                    model.cleanBuildFolder(for: project)
                    NotificationService.post(title: project.name, body: "Build folder cleaned.")
                }
                closePanel()
            }
            .keyboardShortcut("k", modifiers: [.command, .option])
            .disabled(project == nil || engine.isBuilding)

            divider

            PanelRow(icon: "doc", title: "Open Latest IPA", shortcut: "⌘O") {
                FinderActions.reveal(settings.settings.outputURL.appendingPathComponent("latest.ipa"))
                closePanel()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(latest == nil)

            PanelRow(icon: "iphone", title: "Install on Device", shortcut: "⌘I") {
                model.installLatestOnFirstDevice()
                closePanel()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(latest == nil)

            PanelRow(icon: "folder", title: "Open Builds Folder", shortcut: "⇧⌘O") {
                FinderActions.openFolder(settings.settings.outputURL)
                closePanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            divider

            sectionLabel("Recent Builds")

            if history.builds.isEmpty {
                Text("No builds yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(history.builds.prefix(3))) { build in
                    RecentBuildRow(build: build) {
                        FinderActions.reveal(build.outputURL)
                        closePanel()
                    }
                }
            }

            divider

            PanelRow(icon: "gearshape", title: "Open iOS Build Manager", shortcut: nil) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                closePanel()
            }

            PanelRow(icon: "power", title: "Quit iOS Build Manager", shortcut: nil) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(10)
        .frame(width: 340)
        .preferredColorScheme(settings.settings.theme.colorScheme)
    }

    // MARK: - Project row

    private var projectRow: some View {
        HStack(spacing: 10) {
            IconBadge(systemImage: "shippingbox.fill", size: 40)

            VStack(alignment: .leading, spacing: 3) {
                if projects.projects.count > 1 {
                    Menu {
                        ForEach(projects.projects) { p in
                            Button(p.name) { model.selectedProjectId = p.id }
                        }
                    } label: {
                        Text(project?.name ?? "No Project")
                            .font(.headline)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                } else {
                    Text(project?.name ?? "No Project")
                        .font(.headline)
                }

                if let project {
                    HStack(spacing: 12) {
                        chipMenu(title: project.configuration.displayName) {
                            ForEach(BuildConfiguration.allCases) { config in
                                Button(config.displayName) {
                                    projects.update(project.id) { $0.configuration = config }
                                }
                            }
                        }
                        chipMenu(title: destinationShortName(project.destination)) {
                            Button("iOS Device") {
                                projects.update(project.id) { $0.destination = .genericIOS }
                            }
                            Button("Simulator") {
                                projects.update(project.id) { $0.destination = .genericIOSSimulator }
                            }
                            ForEach(devices.devices) { device in
                                Button(device.displayName) {
                                    projects.update(project.id) { $0.destination = device }
                                }
                            }
                        }
                    }
                } else {
                    Text("Add a project to get started")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button {
                model.selection = .settings
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                closePanel()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open project settings")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func chipMenu<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func destinationShortName(_ destination: BuildDestination) -> String {
        switch destination {
        case .genericIOS: return "iOS Device"
        case .genericIOSSimulator: return "Simulator"
        case .connectedDevice(_, let name): return name
        }
    }

    // MARK: - Bits

    private var divider: some View {
        Divider().padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private func closePanel() {
        dismiss()
    }
}

// MARK: - Rows

/// A menu-like row: icon, title, right-aligned shortcut hint, accent hover.
private struct PanelRow: View {
    let icon: String
    let title: String
    let shortcut: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer(minLength: 12)
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(isHovering ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(rowForeground)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering && isEnabled ? Color.accentColor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 && isEnabled }
    }

    private var rowForeground: Color {
        if !isEnabled { return .secondary.opacity(0.5) }
        return isHovering ? .white : .primary
    }
}

/// A recent-build row: status mark, file name, right-aligned relative date.
private struct RecentBuildRow: View {
    let build: BuildRecord
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: build.status == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(build.status == .success ? .green : .red)
                    .frame(width: 20)
                Text(build.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                Text(Self.relativeLabel(build.date))
                    .foregroundStyle(isHovering ? Color.white.opacity(0.8) : Color.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(isHovering ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? Color.accentColor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    /// "Today, 10:41" / "Yesterday" / "2 days ago", like the design.
    static func relativeLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today, " + date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        return "\(days) days ago"
    }
}
