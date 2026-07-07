import XCTest
@testable import iOSBuildManager

final class SchemeParsingTests: XCTestCase {
    func testParsesSchemesFromXcodebuildListOutput() {
        let lines = """
        Command line invocation:
            /usr/bin/xcodebuild -list -project MyApp.xcodeproj

        Information about project "MyApp":
            Targets:
                MyApp
                MyAppTests

            Build Configurations:
                Debug
                Release

            If no build configuration is specified and -scheme is not passed then "Release" is used.

            Schemes:
                MyApp
                MyApp Dev
        """.components(separatedBy: "\n")

        XCTAssertEqual(XcodeBuildService.parseSchemes(lines: lines), ["MyApp", "MyApp Dev"])
    }

    func testReturnsEmptyForEmptyOutput() {
        XCTAssertEqual(XcodeBuildService.parseSchemes(lines: []), [])
    }

    func testStopsAtNextSectionAfterSchemes() {
        let lines = [
            "Schemes:",
            "    OnlyScheme",
            "",
            "Targets:",
            "    ShouldNotAppear"
        ]
        XCTAssertEqual(XcodeBuildService.parseSchemes(lines: lines), ["OnlyScheme"])
    }
}

final class DeviceParsingTests: XCTestCase {
    func testParsesModernAndLegacyUDIDsAndSkipsSimulators() {
        let lines = """
        == Devices ==
        Yam iPhone (18.5) (00008120-001E30E11E78201E)
        Old iPad (12.4) (a1b2c3d4e5f6a7b8c9d0a1b2c3d4e5f6a7b8c9d0)

        == Devices Offline ==

        == Simulators ==
        iPhone 16 Simulator (18.5) (93A43638-0412-52DA-B201-AA8990C2313E)
        """.components(separatedBy: "\n")

        let found = DeviceStore.parseDevices(lines: lines)
        let ids = found.compactMap { destination -> String? in
            if case .connectedDevice(let id, _) = destination { return id }
            return nil
        }

        // Modern 8-16 hex UDID (post-2018 devices).
        XCTAssertTrue(ids.contains("00008120-001E30E11E78201E"))
        // Legacy 40-hex UDID.
        XCTAssertTrue(ids.contains("a1b2c3d4e5f6a7b8c9d0a1b2c3d4e5f6a7b8c9d0"))
        // Simulators must never be offered as install destinations.
        XCTAssertFalse(ids.contains("93A43638-0412-52DA-B201-AA8990C2313E"))
    }

    func testExtractsDeviceNameWithoutUDID() {
        let lines = ["My iPhone (00008120-001E30E11E78201E)"]
        let found = DeviceStore.parseDevices(lines: lines)
        guard case .connectedDevice(_, let name)? = found.first else {
            return XCTFail("expected a connected device")
        }
        XCTAssertEqual(name, "My iPhone")
    }
}

final class SigningIdentityTests: XCTestCase {
    func testTeamIdIsParsedFromCommonName() {
        let identity = SigningIdentity(
            hash: String(repeating: "A", count: 40),
            name: "Apple Development: jane@example.com (ABCDE12345)",
            expirationDate: nil
        )
        XCTAssertEqual(identity.teamId, "ABCDE12345")
        XCTAssertEqual(identity.kind, .development)
    }

    func testDistributionPrefixIsClassified() {
        let identity = SigningIdentity(hash: "", name: "Apple Distribution: ACME Inc (XYZ9876543)", expirationDate: nil)
        XCTAssertEqual(identity.kind, .distribution)
    }

    func testExpiryStates() {
        let expired = SigningIdentity(hash: "", name: "X", expirationDate: Date(timeIntervalSinceNow: -3600))
        XCTAssertTrue(expired.isExpired)
        XCTAssertEqual(expired.statusLabel, "Expired")

        let soon = SigningIdentity(hash: "", name: "X", expirationDate: Date(timeIntervalSinceNow: 5 * 24 * 3600))
        XCTAssertFalse(soon.isExpired)
        XCTAssertTrue(soon.expiresSoon)
        XCTAssertEqual(soon.statusLabel, "Expiring Soon")

        let healthy = SigningIdentity(hash: "", name: "X", expirationDate: Date(timeIntervalSinceNow: 365 * 24 * 3600))
        XCTAssertEqual(healthy.statusLabel, "Valid")
    }
}
