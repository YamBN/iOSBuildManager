import SwiftUI

/// Shown on launch when a newer GitHub release exists.
struct UpdateAvailableSheet: View {
    let update: AvailableUpdate
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                IconBadge(systemImage: "arrow.down.circle.fill", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update Available")
                        .font(.title3.weight(.bold))
                    Text("Version \(update.version) is out — you have \(AppVersion.version).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if !update.releaseNotes.isEmpty {
                ScrollView {
                    Text(update.releaseNotes)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .padding(12)
                .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text("Downloads a DMG from GitHub — installing over the current version is safe, your settings and build history stay put.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Skip This Version") {
                    model.skipUpdate(update.version)
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Later") { dismiss() }
                    .buttonStyle(.bordered)

                Button("Download") {
                    openURL(update.releaseURL)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}
