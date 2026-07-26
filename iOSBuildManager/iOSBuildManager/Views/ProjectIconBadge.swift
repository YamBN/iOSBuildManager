import AppKit
import SwiftUI

/// Shows the icon of the app a project builds — extracted from its most recent
/// built `.app` — falling back to iOS Build Manager's own icon when there's no
/// project or the project hasn't been built yet.
struct ProjectIconBadge: View {
    /// Path to the project's most recent built `.app`, if any.
    let appPath: String?
    /// A user-chosen icon for the project, which wins over the built app's icon.
    var customIconURL: URL?
    var size: CGFloat = 44

    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: size, height: size)
            }
        }
        .task(id: reloadKey) { await loadIcon() }
    }

    private var reloadKey: String {
        "\(customIconURL?.path ?? "")|\(appPath ?? "")"
    }

    @MainActor
    private func loadIcon() async {
        if let customIconURL, let custom = NSImage(contentsOf: customIconURL) {
            icon = custom
            return
        }
        guard let appPath, FileManager.default.fileExists(atPath: appPath) else {
            icon = nil
            return
        }
        if let url = AppIconExtractor.bestIOSIconURL(appPath: appPath) {
            icon = NSImage(contentsOf: url)
        } else {
            // macOS bundle: the Finder icon is the real app icon.
            icon = NSWorkspace.shared.icon(forFile: appPath)
        }
    }
}
