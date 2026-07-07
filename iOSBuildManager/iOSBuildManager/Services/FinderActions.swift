import AppKit
import Foundation

/// Thin wrappers around `NSWorkspace` for revealing/opening files in Finder.
enum FinderActions {
    /// Opens a folder in Finder, or reveals a file selected within its parent.
    static func reveal(_ url: URL) {
        let fm = FileManager.default
        var target = url
        var selecting = [url]
        if fm.fileExists(atPath: url.path) && !url.hasDirectoryPath {
            selecting = [url]
        } else if fm.fileExists(atPath: url.path) && url.hasDirectoryPath {
            target = url
            selecting = []
        }
        if selecting.isEmpty {
            NSWorkspace.shared.open(target)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(selecting)
        }
    }

    /// Opens a folder in Finder.
    static func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Copies a file path to the pasteboard.
    static func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
}
