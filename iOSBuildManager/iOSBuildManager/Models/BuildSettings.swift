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

    var id: String {
        switch self {
        case .genericIOS: return "generic/platform=iOS"
        case .genericIOSSimulator: return "generic/platform=iOS Simulator"
        case .connectedDevice(let id, _): return "device:\(id)"
        }
    }

    var displayName: String {
        switch self {
        case .genericIOS: return "Generic iOS Device"
        case .genericIOSSimulator: return "Generic iOS Simulator"
        case .connectedDevice(_, let name): return name
        }
    }

    var systemImage: String {
        switch self {
        case .genericIOS: return "iphone"
        case .genericIOSSimulator: return "rectangle.dashed"
        case .connectedDevice: return "iphone.radiowaves.left.and.right"
        }
    }

    /// The value passed to `xcodebuild -destination`. `nil` means the caller
    /// needs to build a richer destination string (e.g. for connected devices).
    var xcodebuildDestination: String {
        switch self {
        case .genericIOS: return "generic/platform=iOS"
        case .genericIOSSimulator: return "generic/platform=iOS Simulator"
        case .connectedDevice(let id, _): return "id=\(id)"
        }
    }

    /// Stable list of the "generic" destinations that are always available,
    /// used by pickers before device discovery runs.
    static var defaults: [BuildDestination] {
        [.genericIOS, .genericIOSSimulator]
    }
}
