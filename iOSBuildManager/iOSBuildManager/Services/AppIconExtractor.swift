import Foundation
import ImageIO

/// Pulls the real app icon out of a built `.app` bundle so the UI can show the
/// icon of the *project being built* instead of a generic placeholder.
///
/// iOS bundles flatten their icons to PNGs at the bundle root (e.g.
/// `AppIcon60x60@2x.png`), named in `Info.plist` under `CFBundleIcons`. macOS
/// bundles instead ship an `.icns` the Finder resolves, so for those the caller
/// falls back to `NSWorkspace.icon(forFile:)`.
enum AppIconExtractor {
    /// The highest-resolution iOS icon PNG inside the bundle, or nil when the
    /// bundle has none (e.g. a macOS app, or an app with no icon set).
    nonisolated static func bestIOSIconURL(appPath: String) -> URL? {
        let appURL = URL(fileURLWithPath: appPath)
        let fm = FileManager.default
        guard fm.fileExists(atPath: appURL.path) else { return nil }

        var candidates: [URL] = []

        // Preferred: the base names Info.plist declares as the app's icon.
        if let data = try? Data(contentsOf: appURL.appendingPathComponent("Info.plist")),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
                if let icons = plist[key] as? [String: Any],
                   let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
                   let files = primary["CFBundleIconFiles"] as? [String] {
                    for base in files {
                        candidates += pngs(withBaseName: base, in: appURL)
                    }
                }
            }
        }

        // Fallback: any `AppIcon*.png` flattened at the bundle root.
        if candidates.isEmpty, let all = try? fm.contentsOfDirectory(at: appURL, includingPropertiesForKeys: nil) {
            candidates = all.filter {
                $0.pathExtension.lowercased() == "png" &&
                $0.deletingPathExtension().lastPathComponent.lowercased().hasPrefix("appicon")
            }
        }

        return candidates.max { pixelArea(of: $0) < pixelArea(of: $1) }
    }

    private nonisolated static func pngs(withBaseName base: String, in appURL: URL) -> [URL] {
        guard let all = try? FileManager.default.contentsOfDirectory(at: appURL, includingPropertiesForKeys: nil) else { return [] }
        let baseLower = base.lowercased()
        return all.filter {
            $0.pathExtension.lowercased() == "png" &&
            $0.deletingPathExtension().lastPathComponent.lowercased().hasPrefix(baseLower)
        }
    }

    /// Pixel count read from image metadata — avoids decoding the whole PNG
    /// just to compare sizes.
    private nonisolated static func pixelArea(of url: URL) -> Int {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return 0 }
        return w * h
    }
}
