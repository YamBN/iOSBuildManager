import SwiftUI

/// Custom sidebar matching the dashboard mockup: plain nav list under the
/// traffic lights, subtle pill selection, and the active project pinned to
/// the bottom as a card.
struct Sidebar: View {
    @Binding var selection: SidebarSection
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var branding: BrandingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandingHeader

            VStack(spacing: 4) {
                ForEach(SidebarSection.allCases) { section in
                    SidebarItem(
                        section: section,
                        isSelected: selection == section
                    ) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            Spacer(minLength: 0)

            projectCard
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The app's own logo and name, reflecting whatever the user set in
    /// Settings → Appearance.
    private var brandingHeader: some View {
        HStack(spacing: 9) {
            if let logo = branding.logo(size: 22) {
                Image(nsImage: logo)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
            }
            Text(settings.settings.appDisplayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 34)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var projectCard: some View {
        if let project = model.selectedProject ?? projects.projects.first {
            Button {
                selection = .settings
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(project.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Circle().fill(.green).frame(width: 8, height: 8)
                    }
                    Text(project.fileURL.deletingLastPathComponent().path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(project.isMac ? "macOS App" : "iOS App")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.top, 2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Button {
                selection = .settings
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Add Project")
                        .font(.callout.weight(.medium))
                    Spacer()
                }
                .padding(12)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SidebarItem: View {
    let section: SidebarSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 22)
                Text(section.title)
                    .font(.body)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected
                          ? Color.primary.opacity(0.12)
                          : (isHovering ? Color.primary.opacity(0.06) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
