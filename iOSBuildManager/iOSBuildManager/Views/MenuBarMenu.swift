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

    /// Drives the device-picker flyout that opens to the right of the row.
    /// It opens on hover and stays open while the pointer is over either the
    /// row or the flyout itself; the two `hover` flags feed `syncDevicePicker`.
    @State private var showDevicePicker = false
    @State private var isRowHovered = false
    @State private var isFlyoutHovered = false

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

            installOnDeviceRow

            PanelRow(icon: "folder", title: "Open Builds Folder", shortcut: "⇧⌘O") {
                FinderActions.openFolder(settings.settings.outputURL)
                closePanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            divider

            if engine.isBuilding {
                buildingNowRow
                divider
            }

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
                activateAsRegularApp()
                openWindow(id: "main")
                closePanel()
            }

            PanelRow(icon: "power", title: "Quit iOS Build Manager", shortcut: nil) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(10)
        .frame(width: 340)
        .preferredColorScheme(settings.settings.theme.colorScheme)
        .task { await devices.refresh() }
    }

    // MARK: - Building now

    private var buildingNowRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Building Now")
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.currentProjectName ?? "Building…")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if let progress = engine.estimatedProgress {
                        ProgressView(value: progress, total: 1)
                        Text("\(Int(progress * 100))% • \(BuildProgressEstimator.formattedElapsed(engine.elapsedSeconds))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(BuildProgressEstimator.formattedElapsed(engine.elapsedSeconds)) elapsed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    engine.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel Build")
            }
            .padding(.horizontal, 10)
        }
    }

    // MARK: - Install on device

    /// A plain `PanelRow` (so it lines up pixel-for-pixel with its siblings)
    /// whose disclosure chevron opens a device-picker flyout to the *right*
    /// — the destination is ambiguous with more than one device connected, so
    /// this always shows the list rather than silently guessing.
    private var installOnDeviceRow: some View {
        PanelRow(icon: "iphone", title: "Install on Device", shortcut: nil, showsDisclosure: true) {
            // Click also works, but hover is the primary way in.
            showDevicePicker = true
        }
        .disabled(latest == nil)
        .onHover { hovering in
            isRowHovered = hovering
            if hovering && latest != nil { Task { await devices.refresh() } }
            syncDevicePicker()
        }
        .popover(isPresented: $showDevicePicker, arrowEdge: .trailing) {
            devicePickerFlyout
                .onHover { isFlyoutHovered = $0; syncDevicePicker() }
        }
    }

    /// Opens the flyout as soon as the row is hovered and keeps it open while
    /// the pointer is over the row or the flyout; a short grace period lets the
    /// pointer cross the gap between them without the flyout snapping shut.
    private func syncDevicePicker() {
        guard latest != nil else { return }
        if isRowHovered || isFlyoutHovered {
            showDevicePicker = true
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                if !isRowHovered && !isFlyoutHovered {
                    showDevicePicker = false
                }
            }
        }
    }

    private var devicePickerFlyout: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel("Install On")
            if devices.devices.isEmpty {
                Text(devices.isRefreshing ? "Searching…" : "No devices connected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            } else {
                ForEach(devices.devices) { destination in
                    if case .connectedDevice(let id, let name) = destination {
                        PanelRow(icon: "iphone", title: name, shortcut: nil) {
                            showDevicePicker = false
                            installOnDevice(id: id, name: name)
                        }
                    }
                }
            }
            divider
            PanelRow(icon: "arrow.clockwise", title: "Refresh Devices", shortcut: nil) {
                Task { await devices.refresh() }
            }
        }
        .padding(8)
        .frame(width: 240)
        .preferredColorScheme(settings.settings.theme.colorScheme)
    }

    private func installOnDevice(id: String, name: String) {
        Task {
            let message = await model.installLatestBuildOnDevice(deviceId: id)
            NotificationService.post(title: name, body: message)
        }
        closePanel()
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
                activateAsRegularApp()
                openWindow(id: "main")
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
    var showsDisclosure: Bool = false
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
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isHovering ? Color.white.opacity(0.8) : Color.secondary)
                } else if let shortcut {
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
