import AppKit
import Combine
import SwiftUI

/// Holds the custom icon a user picks for a project.
///
/// An imported image is normalized once — scaled to fit a square canvas at icon
/// resolution, centered, transparent-padded — so a wide screenshot or a tiny
/// favicon both end up as a correct, non-distorted app icon. The normalized PNG
/// is the only thing persisted; every size the build needs is derived from it.
@MainActor
final class BrandingStore: ObservableObject {
    /// Canonical stored size. App icons top out at 1024pt, so normalizing once
    /// at that size means every smaller rendering downsamples cleanly.
    nonisolated static let canonicalSize: CGFloat = 1024

    @Published private(set) var lastError: String?
    /// Bumped whenever an icon file changes, so views re-read from disk.
    @Published private(set) var revision = 0

    // MARK: - Import / remove

    /// Imports an image as the project's icon. Returns false (and sets
    /// `lastError`) when the file isn't a readable image.
    @discardableResult
    func importIcon(from url: URL, projectId: UUID) -> Bool {
        guard let source = NSImage(contentsOf: url), source.size.width > 0, source.size.height > 0 else {
            lastError = "That file isn't a readable image."
            return false
        }
        guard let data = Self.normalizedPNGData(from: source) else {
            lastError = "Could not convert that image."
            return false
        }
        do {
            AppPaths.ensureDirectories()
            try data.write(to: AppPaths.projectIcon(for: projectId), options: .atomic)
        } catch {
            lastError = "Could not save the icon: \(error.localizedDescription)"
            return false
        }
        lastError = nil
        revision += 1
        return true
    }

    func removeIcon(projectId: UUID) {
        try? FileManager.default.removeItem(at: AppPaths.projectIcon(for: projectId))
        lastError = nil
        revision += 1
    }

    func icon(for projectId: UUID) -> NSImage? {
        let url = AppPaths.projectIcon(for: projectId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - Pure helpers (testable)

    /// Scales `source` to fit a square `size`×`size` canvas without distortion,
    /// centering it and leaving the remaining area transparent.
    nonisolated static func normalized(_ source: NSImage, size: CGFloat = canonicalSize) -> NSImage? {
        guard source.size.width > 0, source.size.height > 0 else { return nil }

        let scale = min(size / source.size.width, size / source.size.height)
        let drawn = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        let origin = NSPoint(x: (size - drawn.width) / 2, y: (size - drawn.height) / 2)

        let output = NSImage(size: NSSize(width: size, height: size))
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: origin, size: drawn),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1)
        output.unlockFocus()
        return output
    }

    /// PNG bytes for the normalized form of `source`.
    nonisolated static func normalizedPNGData(from source: NSImage, size: CGFloat = canonicalSize) -> Data? {
        guard let normalized = normalized(source, size: size) else { return nil }
        return pngData(from: normalized, pixelSize: Int(size))
    }

    /// PNG bytes at an exact pixel size — used to rewrite each icon slot inside
    /// a built app bundle at the dimensions that slot expects.
    nonisolated static func pngData(from image: NSImage, pixelSize: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: pixelSize, height: pixelSize)

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }
}
