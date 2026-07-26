import AppKit
import Combine
import SwiftUI

/// Owns the user's custom app branding: a logo image and a display name.
///
/// An imported logo is normalized once — scaled to fit a square canvas at icon
/// resolution, centered, transparent-padded — so a wide screenshot or a tiny
/// favicon both end up as a correct, non-distorted app icon. The normalized PNG
/// is the only thing persisted; every on-screen size is derived from it.
@MainActor
final class BrandingStore: ObservableObject {
    /// Canonical stored size. macOS icons top out at 1024pt, so normalizing
    /// once at that size means every smaller rendering downsamples cleanly.
    nonisolated static let canonicalSize: CGFloat = 1024

    /// The normalized logo, or nil when the user hasn't set one.
    @Published private(set) var logo: NSImage?
    @Published private(set) var lastError: String?

    init() {
        logo = Self.loadStoredLogo()
    }

    var hasCustomLogo: Bool { logo != nil }

    // MARK: - Import / remove

    /// Imports an image file as the custom logo. Returns false (and sets
    /// `lastError`) when the file isn't a readable image.
    @discardableResult
    func importLogo(from url: URL) -> Bool {
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
            try data.write(to: AppPaths.customLogoURL, options: .atomic)
        } catch {
            lastError = "Could not save the logo: \(error.localizedDescription)"
            return false
        }
        lastError = nil
        logo = NSImage(data: data)
        return true
    }

    func removeLogo() {
        try? FileManager.default.removeItem(at: AppPaths.customLogoURL)
        logo = nil
        lastError = nil
    }

    /// Imports a per-project icon, normalized the same way as the app logo.
    @discardableResult
    func importProjectIcon(from url: URL, projectId: UUID) -> Bool {
        guard let source = NSImage(contentsOf: url),
              let data = Self.normalizedPNGData(from: source)
        else {
            lastError = "That file isn't a readable image."
            return false
        }
        do {
            AppPaths.ensureDirectories()
            try data.write(to: AppPaths.projectIcon(for: projectId), options: .atomic)
            lastError = nil
            objectWillChange.send()
            return true
        } catch {
            lastError = "Could not save the icon: \(error.localizedDescription)"
            return false
        }
    }

    func removeProjectIcon(projectId: UUID) {
        try? FileManager.default.removeItem(at: AppPaths.projectIcon(for: projectId))
        objectWillChange.send()
    }

    // MARK: - Rendering

    /// The logo rendered at a specific point size, or nil without a custom logo.
    func logo(size: CGFloat) -> NSImage? {
        guard let logo else { return nil }
        return Self.resized(logo, to: size)
    }

    /// The image to use for the menu bar status item. A custom logo renders at
    /// menu-bar glyph size in full colour; without one, the built-in template
    /// symbol is used so it still adapts to light/dark menu bars.
    func menuBarImage(fallbackSymbol: String) -> NSImage {
        if let custom = logo(size: 18) {
            custom.isTemplate = false
            return custom
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        return image
    }

    // MARK: - Pure helpers (testable)

    /// Scales `source` to fit a square `size`×`size` canvas without distortion,
    /// centering it and leaving the remaining area transparent.
    nonisolated static func normalized(_ source: NSImage, size: CGFloat = canonicalSize) -> NSImage? {
        let canvas = NSSize(width: size, height: size)
        guard source.size.width > 0, source.size.height > 0 else { return nil }

        let scale = min(size / source.size.width, size / source.size.height)
        let drawn = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        let origin = NSPoint(x: (size - drawn.width) / 2, y: (size - drawn.height) / 2)

        let output = NSImage(size: canvas)
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
        guard let normalized = normalized(source, size: size),
              let tiff = normalized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    nonisolated static func resized(_ image: NSImage, to size: CGFloat) -> NSImage {
        let output = NSImage(size: NSSize(width: size, height: size))
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1)
        output.unlockFocus()
        return output
    }

    private static func loadStoredLogo() -> NSImage? {
        guard FileManager.default.fileExists(atPath: AppPaths.customLogoURL.path) else { return nil }
        return NSImage(contentsOf: AppPaths.customLogoURL)
    }
}
