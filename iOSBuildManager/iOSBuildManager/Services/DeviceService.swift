import Foundation

/// Discovers connected physical iOS devices via `xcrun xctrace list devices`.
@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var devices: [BuildDestination] = []
    @Published private(set) var isRefreshing: Bool = false
    @Published var lastError: String?

    func refresh() async {
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        let result: [BuildDestination]
        do {
            result = try await Self.fetchConnectedDevices()
        } catch {
            lastError = error.localizedDescription
            devices = []
            return
        }
        devices = result
    }

    /// All selectable destinations: generic ones plus any connected devices.
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

    nonisolated static func fetchConnectedDevices() async throws -> [BuildDestination] {
        let lines = try await ShellRunner.collect(
            command: "/usr/bin/xcrun",
            arguments: ["xctrace", "list", "devices"]
        )
        return parseDevices(lines: lines)
    }

    nonisolated static func parseDevices(lines: [String]) -> [BuildDestination] {
        var found: [BuildDestination] = []
        // A UDID is 40 hex chars (pre-2018 devices), 8-16 hex (modern devices,
        // e.g. 00008120-001E30E11E78201E), or 8-4-4-4-12 hex (UUID).
        let udidPattern = "([0-9A-Fa-f]{40}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})"
        let regex = try? NSRegularExpression(
            pattern: "^(.*?)\\s+\\(\(udidPattern)\\)(\\s+\\[connected\\])?",
            options: []
        )

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("==") || line.hasSuffix("Simulator") || line == "Mac" { continue }
            guard let regex else { continue }
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, options: [], range: range),
               let nameRange = Range(match.range(at: 1), in: line),
               let idRange = Range(match.range(at: 2), in: line) {
                let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
                let id = String(line[idRange])
                // Skip simulators / Mac entries that occasionally include UDIDs.
                if name.lowercased().contains("simulator") || name == "Mac" { continue }
                found.append(.connectedDevice(id: id, name: name))
            }
        }
        return found
    }
}
