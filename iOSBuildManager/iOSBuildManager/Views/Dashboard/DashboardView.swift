import SwiftUI

/// "Today at 10:57 AM"-style formatter used in the Build Status card.
private let relativeDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter
}()

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var engine: BuildEngine
    @EnvironmentObject private var history: BuildHistoryStore
    @EnvironmentObject private var settings: SettingsStore

    private var quickBuildProject: Project? {
        model.selectedProject ?? model.projects.projects.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Text("Dashboard")
                    .font(.title2.bold())
                    .padding(.bottom, 2)

                if model.signingHealth.needsAttention {
                    SigningWarningBanner(health: model.signingHealth) {
                        if let p = quickBuildProject {
                            model.startBuild(for: p.id)
                            model.selection = .logs
                        } else {
                            model.selection = .settings
                        }
                    }
                }

                HStack(spacing: Theme.spacing) {
                    LatestBuildCard()
                        .frame(maxWidth: .infinity)
                    BuildStatusCard()
                        .frame(width: 340)
                }
                .frame(height: 180)

                QuickActionsCard(quickBuildProject: quickBuildProject)

                RecentBuildsCard()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
        .task { await model.refreshSigning() }
    }
}

// MARK: - Signing warning banner

private struct SigningWarningBanner: View {
    let health: SigningHealth
    let buildNow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: health.systemImage)
                .font(.title2)
                .foregroundStyle(health.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(health.level == .expired ? "Signing Expired" : "Signing Expiring Soon")
                    .font(.subheadline.weight(.semibold))
                Text(health.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let name = health.name {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            Button("Build Now", action: buildNow)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(health.color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(health.color.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Latest build

private struct LatestBuildCard: View {
    @EnvironmentObject private var history: BuildHistoryStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var showingInstallSheet = false

    private var latest: BuildRecord? { history.mostRecentSuccess }

    private var fileLabel: String {
        settings.settings.keepLatestIPA ? "latest.ipa" : (latest?.fileName ?? "")
    }

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Latest Build")

                if let latest {
                    HStack(spacing: 12) {
                        IconBadge(systemImage: "shippingbox.fill", size: 46)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(latest.projectName) \(latest.version) (\(latest.buildNumber))")
                                .font(.title3.weight(.bold))
                            Text(fileLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text(latest.date.formatted(date: .abbreviated, time: .shortened))
                            }
                            HStack(spacing: 8) {
                                Image(systemName: "internaldrive")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text(latest.formattedSize)
                            }
                        }
                        .font(.callout)

                        Spacer()

                        Button("Install on Device") { showingInstallSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    HStack(spacing: 14) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No builds yet")
                                .font(.headline)
                            Text("Build a project to create your first IPA.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                }

                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .sheet(isPresented: $showingInstallSheet) {
            InstallOnDeviceSheet()
        }
    }
}

// MARK: - Status

private struct BuildStatusCard: View {
    @EnvironmentObject private var engine: BuildEngine
    @EnvironmentObject private var history: BuildHistoryStore

    private var lastRecord: BuildRecord? { history.mostRecent }

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Build Status")

                if engine.isBuilding {
                    HStack(alignment: .top, spacing: 14) {
                        StatusCircle(systemImage: "gearshape.2.fill", color: .blue, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Building…")
                                .font(.title3.weight(.bold))
                            Text(engine.currentProjectName ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Button(role: .destructive) { engine.cancel() } label: {
                                Label("Cancel", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.top, 4)
                        }
                    }
                } else if let record = lastRecord {
                    HStack(alignment: .top, spacing: 14) {
                        StatusCircle(
                            systemImage: statusGlyph(record.status),
                            color: Theme.statusColor(record.status),
                            size: 56
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(headline(record.status))
                                .font(.title3.weight(.bold))
                            Text(relativeDateFormatter.string(from: record.date))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(record.formattedDuration)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        StatusCircle(systemImage: "circle.dotted", color: .gray, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Idle")
                                .font(.title3.weight(.bold))
                            Text("No builds yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let err = engine.lastError, !engine.isBuilding {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func headline(_ status: BuildStatus) -> String {
        switch status {
        case .success: return "Build Succeeded"
        case .failed: return "Build Failed"
        case .cancelled: return "Build Cancelled"
        case .building: return "Building…"
        case .idle: return "Idle"
        }
    }

    private func statusGlyph(_ status: BuildStatus) -> String {
        switch status {
        case .success: return "checkmark"
        case .failed: return "xmark"
        case .cancelled: return "stop.fill"
        case .building: return "gearshape.2.fill"
        case .idle: return "circle.dotted"
        }
    }
}

// MARK: - Install on device

struct InstallOnDeviceSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var devices: DeviceStore
    @Environment(\.dismiss) private var dismiss
    @State private var isInstalling = false
    @State private var resultMessage: String?

    private var connectedDevices: [BuildDestination] { devices.devices }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install on Device")
                .font(.headline)
            Text("Installs the most recent successful build onto a connected, trusted device.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if devices.isRefreshing {
                ProgressView("Scanning for devices…")
            } else if connectedDevices.isEmpty {
                EmptyStateView(
                    title: "No Devices Found",
                    systemImage: "iphone.slash",
                    description: Text("Connect an iPhone via USB or Wi-Fi and trust this Mac.")
                )
                .frame(height: 140)
            } else {
                VStack(spacing: 0) {
                    ForEach(connectedDevices) { destination in
                        Button {
                            install(destination)
                        } label: {
                            HStack {
                                Image(systemName: destination.systemImage)
                                Text(destination.displayName)
                                Spacer()
                                if isInstalling { ProgressView().controlSize(.small) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                        .disabled(isInstalling)
                        if destination.id != connectedDevices.last?.id { Divider() }
                    }
                }
            }

            if let resultMessage {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 380)
        .task { await devices.refresh() }
    }

    private func install(_ destination: BuildDestination) {
        guard case .connectedDevice(let id, _) = destination else { return }
        isInstalling = true
        Task {
            resultMessage = await model.installLatestBuildOnDevice(deviceId: id)
            isInstalling = false
        }
    }
}

// MARK: - Quick actions

private struct QuickActionsCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    let quickBuildProject: Project?

    @State private var showingInstallSheet = false
    @State private var cleanedMessage: String?

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Quick Actions")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    QuickActionTile(title: "Create Build", systemImage: "play.fill", circled: true) {
                        if let p = quickBuildProject {
                            model.startBuild(for: p.id)
                            model.selection = .logs
                        } else {
                            model.selection = .settings
                        }
                    }
                    QuickActionTile(title: "Open Builds Folder", systemImage: "folder") {
                        FinderActions.openFolder(settings.settings.outputURL)
                    }
                    QuickActionTile(title: "Install on Device", systemImage: "iphone") {
                        showingInstallSheet = true
                    }
                    QuickActionTile(title: "Clean Old Builds", systemImage: "trash") {
                        model.cleanOldBuilds()
                        cleanedMessage = "Old builds cleaned up."
                    }
                }
                if let cleanedMessage {
                    Text(cleanedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingInstallSheet) {
            InstallOnDeviceSheet()
        }
    }
}

// MARK: - Recent builds

private struct RecentBuildsCard: View {
    @EnvironmentObject private var history: BuildHistoryStore
    @EnvironmentObject private var model: AppModel

    private var recent: [BuildRecord] { Array(history.builds.prefix(5)) }

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Recent Builds")

                if recent.isEmpty {
                    Text("No builds yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
                } else {
                    columnHeader
                        .padding(.top, 2)
                    VStack(spacing: 0) {
                        ForEach(recent) { build in
                            buildRow(build)
                        }
                    }
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack {
            Text("Version").frame(width: 110, alignment: .leading)
            Text("Build").frame(width: 90, alignment: .leading)
            Text("Date").frame(maxWidth: .infinity, alignment: .leading)
            Text("Size").frame(width: 110, alignment: .leading)
            Text("Status").frame(width: 60, alignment: .leading)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func buildRow(_ build: BuildRecord) -> some View {
        HStack {
            Text(build.version).frame(width: 110, alignment: .leading)
            Text(build.buildNumber).frame(width: 90, alignment: .leading)
            Text(build.date.formatted(date: .abbreviated, time: .shortened))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(build.formattedSize).frame(width: 110, alignment: .leading)
            statusMark(build.status)
                .frame(width: 60, alignment: .leading)
        }
        .font(.callout)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { FinderActions.reveal(build.outputURL) }
    }

    @ViewBuilder
    private func statusMark(_ status: BuildStatus) -> some View {
        switch status {
        case .success:
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark")
                .fontWeight(.semibold)
                .foregroundStyle(.red)
        default:
            Image(systemName: status.systemImage)
                .foregroundStyle(Theme.statusColor(status))
        }
    }
}
