import Foundation

/// Xcode build configuration chosen by the user.
enum BuildConfiguration: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case debug = "Debug"
    case release = "Release"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var systemImage: String {
        switch self {
        case .debug: return "ladybug"
        case .release: return "shippingbox"
        }
    }
}

/// A selectable build destination. `connectedDevice` carries the device id
/// and human readable name reported by `xcrun xctrace list devices` /
/// `instruments -s devices`.
enum BuildDestination: Codable, Hashable, Sendable, Identifiable {
    case genericIOS
    case genericIOSSimulator
    case connectedDevice(id: String, name: String)
    case macOS

    var id: String {
        switch self {
        case .genericIOS: return "generic/platform=iOS"
        case .genericIOSSimulator: return "generic/platform=iOS Simulator"
        case .connectedDevice(let id, _): return "device:\(id)"
        case .macOS: return "platform=macOS"
        }
    }

    var displayName: String {
        switch self {
        case .genericIOS: return "Generic iOS Device"
        case .genericIOSSimulator: return "Generic iOS Simulator"
        case .connectedDevice(_, let name): return name
        case .macOS: return "My Mac"
        }
    }

    var systemImage: String {
        switch self {
        case .genericIOS: return "iphone"
        case .genericIOSSimulator: return "rectangle.dashed"
        case .connectedDevice: return "iphone.radiowaves.left.and.right"
        case .macOS: return "macbook"
        }
    }

    /// The value passed to `xcodebuild -destination`. `nil` means the caller
    /// needs to build a richer destination string (e.g. for connected devices).
    var xcodebuildDestination: String {
        switch self {
        case .genericIOS: return "generic/platform=iOS"
        case .genericIOSSimulator: return "generic/platform=iOS Simulator"
        case .connectedDevice(let id, _): return "id=\(id)"
        case .macOS: return "platform=macOS"
        }
    }

    var isMac: Bool {
        if case .macOS = self { return true }
        return false
    }

    /// Stable list of the "generic" destinations that are always available,
    /// used by pickers before device discovery runs.
    static var defaults: [BuildDestination] {
        [.genericIOS, .genericIOSSimulator]
    }
}

/// The platform a project's selected scheme builds for, detected from
/// `xcodebuild -showBuildSettings`. Drives which destinations and export
/// formats the UI offers.
enum ProjectPlatform: String, Codable, Sendable, Hashable {
    case iOS
    case macOS
    case unknown
}

/// How a finished build is packaged for distribution. iOS builds become an
/// `.ipa`; macOS builds can be a zipped `.app` or a `.dmg`.
enum ExportFormat: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case ipa
    case appZip
    case dmg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ipa: return "IPA"
        case .appZip: return "App (.zip)"
        case .dmg: return "DMG"
        }
    }

    var fileExtension: String {
        switch self {
        case .ipa: return "ipa"
        case .appZip: return "zip"
        case .dmg: return "dmg"
        }
    }

    /// Formats offered for a platform, most-recommended first.
    static func formats(for platform: ProjectPlatform) -> [ExportFormat] {
        switch platform {
        case .macOS: return [.dmg, .appZip]
        case .iOS, .unknown: return [.ipa]
        }
    }
}
