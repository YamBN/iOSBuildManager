import AppKit
import Foundation

/// Applies a project's custom icon and display name to a freshly built `.app`,
/// before it gets packaged, so the app you actually install carries them.
///
/// Editing a bundle invalidates its code signature, so anything changed here is
/// re-signed afterwards with the identity it already had (entitlements
/// preserved), falling back to ad-hoc.
enum BuildBrandingService {
    /// Icon slot sizes an `.icns` needs, as (pixel size, iconset filename).
    static let icnsSlots: [(size: Int, name: String)] = [
        (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
    ]

    /// Applies branding, returning log lines describing what changed.
    /// Does nothing (and returns no lines) when the project has no overrides.
    ///
    /// Takes the icon as a URL rather than an image because `NSImage` isn't
    /// `Sendable`; it's loaded here, off the caller's actor.
    static func apply(
        iconURL: URL?,
        displayName: String?,
        to appURL: URL,
        isMac: Bool
    ) async -> [String] {
        let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = iconURL.flatMap { NSImage(contentsOf: $0) }
        guard icon != nil || !name.isEmpty else { return [] }

        var log: [String] = []
        let plistURL = infoPlistURL(in: appURL, isMac: isMac)
        guard var plist = readPlist(at: plistURL) else {
            return ["▸ ⚠️ Could not read Info.plist — skipping custom branding."]
        }

        if !name.isEmpty {
            plist["CFBundleDisplayName"] = name
            plist["CFBundleName"] = name
            log.append("▸ Set app name to “\(name)”.")
        }

        if let icon {
            do {
                if isMac {
                    try applyMacIcon(icon, to: appURL, plist: &plist)
                    log.append("▸ Replaced the app icon (AppIcon.icns).")
                } else {
                    let count = try applyIOSIcons(icon, in: appURL)
                    log.append(count > 0
                        ? "▸ Replaced \(count) app icon image\(count == 1 ? "" : "s")."
                        : "▸ ⚠️ No icon images found in the bundle to replace.")
                }
            } catch {
                log.append("▸ ⚠️ Could not apply the custom icon: \(error.localizedDescription)")
            }
        }

        guard writePlist(plist, to: plistURL) else {
            return log + ["▸ ⚠️ Could not write Info.plist — branding may be incomplete."]
        }

        log.append(contentsOf: await resign(appURL: appURL))
        return log
    }

    static func infoPlistURL(in appURL: URL, isMac: Bool) -> URL {
        appURL.appendingPathComponent(isMac ? "Contents/Info.plist" : "Info.plist")
    }

    // MARK: - macOS icon

    /// Writes an `.icns` into the bundle and points Info.plist at it.
    ///
    /// `CFBundleIconName` (the asset-catalog icon) takes precedence over
    /// `CFBundleIconFile`, so it has to be removed for the replacement to win.
    private static func applyMacIcon(_ icon: NSImage, to appURL: URL, plist: inout [String: Any]) throws {
        let resources = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        let icns = try makeICNS(from: icon)
        try icns.write(to: resources.appendingPathComponent("AppIcon.icns"), options: .atomic)

        plist["CFBundleIconFile"] = "AppIcon"
        plist.removeValue(forKey: "CFBundleIconName")
    }

    /// Builds `.icns` bytes by writing an iconset and running `iconutil`.
    static func makeICNS(from icon: NSImage) throws -> Data {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("icns-\(UUID().uuidString)", isDirectory: true)
        let iconset = workDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        for slot in icnsSlots {
            guard let data = BrandingStore.pngData(from: icon, pixelSize: slot.size) else {
                throw BuildError.packagingFailed("Could not render icon at \(slot.size)px")
            }
            try data.write(to: iconset.appendingPathComponent(slot.name))
        }

        let output = workDir.appendingPathComponent("AppIcon.icns")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0, let data = try? Data(contentsOf: output) else {
            throw BuildError.packagingFailed("iconutil could not build the .icns")
        }
        return data
    }

    // MARK: - iOS icons

    /// Overwrites each icon PNG already in the bundle, keeping its filename and
    /// pixel dimensions so `Info.plist` keeps resolving it. Returns how many
    /// were replaced.
    @discardableResult
    static func applyIOSIcons(_ icon: NSImage, in appURL: URL) throws -> Int {
        let targets = iconFileURLs(in: appURL)
        var replaced = 0
        for url in targets {
            guard let pixels = pixelSize(of: url) else { continue }
            guard let data = BrandingStore.pngData(from: icon, pixelSize: pixels) else { continue }
            try data.write(to: url, options: .atomic)
            replaced += 1
        }
        return replaced
    }

    /// Icon PNGs flattened at the bundle root, which is where iOS keeps the
    /// primary app icon regardless of the asset catalog.
    static func iconFileURLs(in appURL: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: appURL, includingPropertiesForKeys: nil) else { return [] }
        return contents.filter { url in
            guard url.pathExtension.lowercased() == "png" else { return false }
            return url.deletingPathExtension().lastPathComponent.lowercased().hasPrefix("appicon")
        }
    }

    /// Square pixel dimension of a PNG, read from metadata.
    static func pixelSize(of url: URL) -> Int? {
        guard let rep = NSImageRep(contentsOf: url) else { return nil }
        let pixels = max(rep.pixelsWide, rep.pixelsHigh)
        return pixels > 0 ? pixels : nil
    }

    // MARK: - Re-signing

    /// Re-signs after the bundle was modified, preserving entitlements so an
    /// iOS build stays installable with the profile it was built against.
    private static func resign(appURL: URL) async -> [String] {
        let authority = await XcodeBuildService.codesignAuthority(at: appURL)
        let identity = (authority == nil || authority == "ad-hoc" || authority == "signed (unknown authority)")
            ? "-"
            : authority!

        if await runCodesign(identity: identity, appURL: appURL) {
            return ["▸ Re-signed after branding (\(identity == "-" ? "ad-hoc" : identity))."]
        }
        if identity != "-", await runCodesign(identity: "-", appURL: appURL) {
            return ["▸ ⚠️ Could not re-sign with “\(identity)”; used an ad-hoc signature instead. SideStore/AltStore will re-sign on install."]
        }
        return ["▸ ⚠️ Branding applied but re-signing failed — the signature is now invalid."]
    }

    private static func runCodesign(identity: String, appURL: URL) async -> Bool {
        let lines = try? await ShellRunner.collect(
            command: "/usr/bin/codesign",
            arguments: ["--force", "--sign", identity,
                        "--preserve-metadata=entitlements,requirements,flags",
                        appURL.path]
        )
        // codesign reports success on stderr as "<path>: replacing existing signature".
        guard let lines else { return false }
        return !lines.contains { $0.lowercased().contains("error") || $0.contains("failed") }
    }

    // MARK: - plist helpers

    static func readPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return plist
    }

    @discardableResult
    static func writePlist(_ plist: [String: Any], to url: URL) -> Bool {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return false
        }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
