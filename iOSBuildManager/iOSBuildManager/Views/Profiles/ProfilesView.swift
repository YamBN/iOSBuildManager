import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var profiles: ProvisioningProfileStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header
                teamCard
                profilesCard
            }
            .padding(20)
        }
        .navigationTitle("Profiles")
        .task { await profiles.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Provisioning Profiles")
                .font(.largeTitle.weight(.bold))
            Text("Installed under ~/Library/MobileDevice/Provisioning Profiles.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var teamCard: some View {
        GlassPanel {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profiles.primaryTeamName ?? "No Team Detected")
                        .font(.title3.weight(.semibold))
                    if let teamId = profiles.primaryTeamId {
                        Text("Team ID: \(teamId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Import a profile to detect your team.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if profiles.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await profiles.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var profilesCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Profiles", systemImage: "doc.badge.gearshape")
                    Spacer()
                    Button {
                        Task { await profiles.importProfile() }
                    } label: {
                        Label("Import Profile", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if let err = profiles.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                if profiles.profiles.isEmpty {
                    EmptyStateView(
                        title: "No Provisioning Profiles",
                        systemImage: "doc.badge.gearshape",
                        description: Text("Import a .mobileprovision file, or build a project in Xcode with automatic signing to install one.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    VStack(spacing: 0) {
                        ForEach(profiles.profiles) { profile in
                            profileRow(profile)
                            if profile.id != profiles.profiles.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func profileRow(_ profile: ProvisioningProfile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: profile.kind.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name).font(.callout.weight(.medium))
                if let expiration = profile.expirationDate {
                    Text("Expires \(expiration.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(profile.kind.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            statusPill(profile.statusLabel)
            Menu {
                Button { FinderActions.reveal(profile.fileURL) } label: { Label("Reveal in Finder", systemImage: "finder") }
                Button(role: .destructive) { profiles.remove(profile) } label: { Label("Remove", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
        }
        .padding(.vertical, 8)
    }

    private func statusPill(_ label: String) -> some View {
        let color: Color = label == "Valid" ? .green : (label == "Expiring Soon" ? .orange : .red)
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}
