import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var devices: DeviceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header
                summaryCard
                devicesCard
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
            Text("Connected Devices")
                .font(.largeTitle.weight(.bold))
            Text("Detected via `xcrun xctrace list devices`.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var summaryCard: some View {
        GlassPanel {
            HStack {
                stat("Detected", "\(devices.devices.count)", "iphone.radiowaves.left.and.right")
                Divider().frame(height: 36)
                stat("Generic Destinations", "\(BuildDestination.defaults.count)", "rectangle.dashed")
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
                SectionHeader(title: "Connected iOS Devices", systemImage: "iphone")
                if devices.isRefreshing {
                    HStack { ProgressView(); Text("Scanning…") }
                } else if devices.devices.isEmpty {
                    Text("No connected devices found. Plug in an iPhone and tap Refresh.")
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

    private var helpCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Tips", systemImage: "lightbulb")
                Text("• Trust the computer on the iPhone after plugging in.")
                Text("• Install the free Apple ID via Xcode → Settings → Accounts.")
                Text("• For SideStore/AltStore, the IPA is dropped into iCloud Builds.")
                Text("• Simulator destinations produce iphonesimulator builds (not installable on device).")
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}
