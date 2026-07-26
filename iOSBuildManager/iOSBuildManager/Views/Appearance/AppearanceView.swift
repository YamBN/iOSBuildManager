import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Customizes the app **being built**: its icon and its display name. Both are
/// written into the `.app` on the next build, so the app you install carries
/// them — they're not just labels inside this manager.
struct AppearanceView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var branding: BrandingStore
    @EnvironmentObject private var history: BuildHistoryStore

    /// Preview background only — this changes nothing about the build.
    @State private var previewDark = true
    @State private var isDropTargeted = false

    private var project: Project? { model.selectedProject ?? projects.projects.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header

                if let project {
                    iconCard(project)
                    nameCard(project)
                    appliesCard(project)
                } else {
                    GlassPanel {
                        Text("Add a project in Settings to customize how it looks.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Theme.spacing)
        }
        .navigationTitle("Appearance")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Appearance").font(.largeTitle.weight(.bold))
            Text(project.map { "Icon and name applied to “\($0.name)” when it's built" }
                 ?? "Icon and name applied to your project when it's built")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Icon

    private func iconCard(_ project: Project) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "App Icon", systemImage: "app")
                    Spacer()
                    Picker("", selection: $previewDark) {
                        Label("Dark", systemImage: "moon.fill").tag(true)
                        Label("Light", systemImage: "sun.max.fill").tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    .help("Preview the icon on a dark or light background")
                }

                HStack(alignment: .top, spacing: 18) {
                    iconWell(project)

                    VStack(alignment: .leading, spacing: 10) {
                        previewStrip(project)

                        HStack(spacing: 8) {
                            Button("Choose Image…") { chooseIcon(for: project) }
                            if project.customIconURL != nil {
                                Button("Remove") {
                                    branding.removeIcon(projectId: project.id)
                                    projects.update(project.id) { $0.hasCustomIcon = false }
                                }
                            }
                        }

                        Text("Any image works — it's scaled to fit a square icon without stretching, then written at every size the app bundle needs. Drop one on the square or click to choose.")
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

    private func iconWell(_ project: Project) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(previewDark ? Color.black.opacity(0.55) : Color.white.opacity(0.85))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.primary.opacity(0.15),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1,
                                       dash: project.customIconURL == nil ? [5] : [])
                )

            if let icon = currentIcon(project) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            } else {
                VStack(spacing: 5) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("Drop icon").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 132, height: 132)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers, for: project)
        }
        .onTapGesture { chooseIcon(for: project) }
    }

    /// The icon at the sizes the platform actually shows it at, on the chosen
    /// background — this is where a logo with thin strokes gives itself away.
    private func previewStrip(_ project: Project) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            ForEach([64, 32, 16], id: \.self) { size in
                VStack(spacing: 4) {
                    Group {
                        if let icon = currentIcon(project) {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .clipShape(RoundedRectangle(cornerRadius: CGFloat(size) * 0.22, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: CGFloat(size) * 0.22, style: .continuous)
                                .fill(Color.primary.opacity(0.12))
                        }
                    }
                    .frame(width: CGFloat(size), height: CGFloat(size))
                    Text("\(size)pt").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(previewDark ? Color.black.opacity(0.55) : Color.white.opacity(0.85))
        )
    }

    /// The custom icon if set, otherwise the icon from the project's last build.
    private func currentIcon(_ project: Project) -> NSImage? {
        if let custom = branding.icon(for: project.id) { return custom }
        guard let appPath = history.mostRecentSuccess(for: project.id)?.appPath else { return nil }
        if let url = AppIconExtractor.bestIOSIconURL(appPath: appPath) {
            return NSImage(contentsOf: url)
        }
        return FileManager.default.fileExists(atPath: appPath)
            ? NSWorkspace.shared.icon(forFile: appPath)
            : nil
    }

    // MARK: - Name

    private func nameCard(_ project: Project) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "App Name", systemImage: "textformat")
                TextField(project.name, text: Binding(
                    get: { project.displayNameOverride ?? "" },
                    set: { newValue in
                        projects.update(project.id) { $0.displayNameOverride = newValue.isEmpty ? nil : newValue }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)

                Text("Written to the bundle's display name, so this is what shows under the icon once it's installed. Leave empty to keep the project's own name.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Explanation

    private func appliesCard(_ project: Project) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label("Applied on the next build", systemImage: "info.circle")
                    .font(.subheadline.weight(.medium))
                Text(project.isMac
                     ? "The icon is written as AppIcon.icns and the name into Info.plist, then the app is re-signed."
                     : "The icon replaces the images inside the .app and the name goes into Info.plist, then the app is re-signed. SideStore and AltStore re-sign again on install.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    model.startBuild(for: project.id)
                    model.selection = .logs
                } label: {
                    Label("Build Now", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(project.selectedScheme == nil)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Picking

    private func chooseIcon(for project: Project) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an icon for \(project.name)"
        panel.prompt = "Use"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyIcon(url, to: project)
    }

    private func handleDrop(_ providers: [NSItemProvider], for project: Project) -> Bool {
        guard let provider = providers.first else { return false }
        let projectId = project.id
        let branding = branding
        let projects = projects
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                if branding.importIcon(from: url, projectId: projectId) {
                    projects.update(projectId) { $0.hasCustomIcon = true }
                }
            }
        }
        return true
    }

    private func applyIcon(_ url: URL, to project: Project) {
        if branding.importIcon(from: url, projectId: project.id) {
            projects.update(project.id) { $0.hasCustomIcon = true }
        }
    }
}
