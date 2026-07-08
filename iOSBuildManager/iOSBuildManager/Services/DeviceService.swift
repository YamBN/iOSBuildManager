import Foundation

/// A paired device that is currently unreachable (powered off, locked away,
/// or not on the same network). Shown for context only — never offered as an
/// install destination.
struct OfflineDevice: Identifiable, Hashable, Sendable {
    var id: String  // hardware UDID
    var name: String
    var model: String?
}

/// Discovers physical iOS devices via `xcrun devicectl list devices` (JSON).
///
/// devicectl is also the tool used for installs, so its view of the world is
/// the accurate one: it never lists the Mac itself, and it distinguishes
/// devices with an active connection (`tunnelState == connected`) from ones
/// that are merely paired but unreachable right now.
@MainActor
final class DeviceStore: ObservableObject {
    /// Devices that can receive a direct install right now.
    @Published private(set) var devices: [BuildDestination] = []
    /// Paired devices that are currently unreachable.
    @Published private(set) var offlineDevices: [OfflineDevice] = []
    @Published private(set) var isRefreshing: Bool = false
    @Published var lastError: String?

    func refresh() async {
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            let result = try await Self.fetchDevices()
            devices = result.connected
            offlineDevices = result.offline
        } catch {
            lastError = error.localizedDescription
            devices = []
            offlineDevices = []
        }
    }

    /// All selectable destinations: generic ones plus reachable devices.
    var allDestinations: [BuildDestination] {
        BuildDestination.defaults + devices
    }

    /// Installs a built `.app` onto a connected device via `devicectl`.
    /// Requires the app to already be signed with a profile valid for that device.
    func install(appPath: String, deviceId: String) async throws {
        for try await _ in ShellRunner.stream(
            command: "/usr/bin/xcrun",
            arguments: ["devicectl", "device", "install", "app", "--device", deviceId, appPath],
            throwOnNonZero: true
        ) {}
    }

    nonisolated static func fetchDevices() async throws -> (connected: [BuildDestination], offline: [OfflineDevice]) {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("devicectl-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }

        _ = try await ShellRunner.collect(
            command: "/usr/bin/xcrun",
            arguments: ["devicectl", "list", "devices", "--json-output", output.path]
        )
        guard let data = try? Data(contentsOf: output) else { return ([], []) }
        return parse(devicectlJSON: data)
    }

    /// Parses `devicectl list devices --json-output` content. Devices with an
    /// active tunnel become install destinations; paired-but-unreachable ones
    /// are reported separately.
    nonisolated static func parse(devicectlJSON data: Data) -> (connected: [BuildDestination], offline: [OfflineDevice]) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let entries = result["devices"] as? [[String: Any]]
        else { return ([], []) }

        var connected: [BuildDestination] = []
        var offline: [OfflineDevice] = []

        for entry in entries {
            let hardware = entry["hardwareProperties"] as? [String: Any]
            let properties = entry["deviceProperties"] as? [String: Any]
            let connection = entry["connectionProperties"] as? [String: Any]

            guard let udid = hardware?["udid"] as? String else { continue }
            let name = (properties?["name"] as? String)
                ?? (hardware?["marketingName"] as? String)
                ?? "Unknown Device"

            let tunnelState = ((connection?["tunnelState"] as? String) ?? "").lowercased()
            if tunnelState == "connected" {
                connected.append(.connectedDevice(id: udid, name: name))
            } else {
                offline.append(OfflineDevice(
                    id: udid,
                    name: name,
                    model: hardware?["marketingName"] as? String
                ))
            }
        }
        return (connected, offline)
    }
}
