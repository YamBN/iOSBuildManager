import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Customization: the app's own logo and name, the colour theme, and
/// per-project icon/name overrides.
struct AppearanceSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var branding: BrandingStore
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var history: BuildHistoryStore

    @State private var isDropTargeted = false

    private var project: Project? { model.selectedProject ?? projects.projects.first }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            appBrandingCard
            themeCard
            projectBrandingCard
        }
    }

    // MARK: - App branding

    private var appBrandingCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "App Branding", systemImage: "paintbrush")

                HStack(alignment: .top, spacing: 16) {
                    logoWell

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("App Name").font(.subheadline.weight(.medium))
                            TextField("iOS Build Manager", text: Binding(
                                get: { settings.settings.customAppName },
                                set: { settings.settings.customAppName = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                        }

                        HStack(spacing: 8) {
                            Button("Choose Logo…") { chooseLogo() }
                            if branding.hasCustomLogo {
                                Button("Remove") { branding.removeLogo() }
                            }
                        }

                        Text("Any image works — it's scaled to fit a square icon without stretching, so the Dock, menu bar, and sidebar all get the right size. Changes apply immediately.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let error = branding.lastError {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var logoWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.primary.opacity(0.15),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: branding.hasCustomLogo ? [] : [5])
                )

            if let logo = branding.logo(size: 72) {
                Image(nsImage: logo)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    Text("Drop logo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 104, height: 104)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDroppedImage(providers) { url in
                branding.importLogo(from: url)
            }
        }
        .onTapGesture { chooseLogo() }
        .help("Click or drop an image to set a custom app logo")
    }

    // MARK: - Theme

    private var themeCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Appearance", systemImage: "circle.lefthalf.filled")
                Picker("", selection: Binding(
                    get: { settings.settings.theme },
                    set: { settings.settings.theme = $0 }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.displayName, systemImage: theme.systemImage).tag(theme)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Text("System follows your Mac's light/dark setting.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Per-project

    @ViewBuilder
    private var projectBrandingCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Project Branding", systemImage: "app.badge")

                if let project {
                    HStack(alignment: .top, spacing: 16) {
                        ProjectIconBadge(
                            appPath: history.mostRecentSuccess(for: project.id)?.appPath,
                            customIconURL: project.customIconURL,
                            size: 64
                        )
                        .id(project.customIconURL?.path ?? "none")

                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Display Name").font(.subheadline.weight(.medium))
                                TextField(project.name, text: Binding(
                                    get: { project.displayNameOverride ?? "" },
                                    set: { newValue in
                                        projects.update(project.id) { $0.displayNameOverride = newValue }
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 260)
                            }

                            HStack(spacing: 8) {
                                Button("Choose Icon…") { chooseProjectIcon(for: project) }
                                if project.customIconURL != nil {
                                    Button("Remove") {
                                        branding.removeProjectIcon(projectId: project.id)
                                        projects.update(project.id) { $0.hasCustomIcon = false }
                                    }
                                }
                            }

                            Text("Overrides how “\(project.name)” appears in the sidebar, dashboard, and menu bar. Without a custom icon, the icon from its last build is used.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    Text("Add a project to customize it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Pickers

    private func chooseLogo() {
        guard let url = runImagePanel(message: "Choose an image to use as the app logo") else { return }
        branding.importLogo(from: url)
    }

    private func chooseProjectIcon(for project: Project) {
        guard let url = runImagePanel(message: "Choose an icon for \(project.name)") else { return }
        if branding.importProjectIcon(from: url, projectId: project.id) {
            projects.update(project.id) { $0.hasCustomIcon = true }
        }
    }

    private func runImagePanel(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = message
        panel.prompt = "Use"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Pulls a file URL out of a drop and hands it to `apply` on the main actor.
    /// `apply` is `@Sendable` because the provider calls back off the main
    /// thread; the stores it captures are `@MainActor` classes, so sending them
    /// is safe.
    private func loadDroppedImage(_ providers: [NSItemProvider], apply: @escaping @Sendable (URL) -> Void) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in apply(url) }
        }
        return true
    }
}
