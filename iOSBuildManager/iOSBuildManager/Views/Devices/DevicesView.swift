import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var devices: DeviceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header
                summaryCard
                devicesCard
                if !devices.offlineDevices.isEmpty {
                    offlineCard
                }
                helpCard
            }
            .padding(20)
        }
        .navigationTitle("Devices")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await devices.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(devices.isRefreshing)
            }
        }
        .task { await devices.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Devices")
                .font(.largeTitle.weight(.bold))
            Text("Detected via `xcrun devicectl list devices`. Only devices with an active connection can receive direct installs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var summaryCard: some View {
        GlassPanel {
            HStack {
                stat("Connected", "\(devices.devices.count)", "iphone.radiowaves.left.and.right")
                Divider().frame(height: 36)
                stat("Paired, Offline", "\(devices.offlineDevices.count)", "iphone.slash")
                if let err = devices.lastError {
                    Divider().frame(height: 36)
                    stat("Last Error", err, "exclamationmark.triangle")
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.callout.weight(.semibold)).lineLimit(2)
            }
        }
    }

    private var devicesCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Connected Devices", systemImage: "iphone")
                if devices.isRefreshing {
                    HStack { ProgressView(); Text("Scanning…") }
                } else if devices.devices.isEmpty {
                    Text("No reachable devices. Plug in an iPhone — or make sure it's awake and on the same network — then tap Refresh.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(devices.devices) { device in
                            HStack {
                                Image(systemName: device.systemImage).foregroundStyle(Color.accentColor).frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(device.displayName).font(.callout.weight(.medium))
                                    Text(device.id).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Connected")
                                    .font(.caption2)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.green.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.green)
                            }
                            .padding(.vertical, 8)
                            if device.id != devices.devices.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private var offlineCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Paired, Currently Offline", systemImage: "iphone.slash")
                Text("Paired with this Mac but unreachable right now (powered off or on a different network) — they can't receive direct installs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(devices.offlineDevices) { device in
                        HStack {
                            Image(systemName: "iphone.slash")
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.name).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                                Text(device.model ?? device.id).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text("Offline")
                                .font(.caption2)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        if device.id != devices.offlineDevices.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var helpCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Tips", systemImage: "lightbulb")
                Text("• Trust the computer on the iPhone after plugging in.")
                Text("• Wi-Fi installs need the device awake and on the same network.")
                Text("• Install the free Apple ID via Xcode → Settings → Accounts.")
                Text("• For SideStore/AltStore, the IPA is dropped into iCloud Builds.")
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}
