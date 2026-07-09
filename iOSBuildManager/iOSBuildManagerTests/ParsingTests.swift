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
    /// Shapes match real `devicectl list devices --json-output` content.
    private func fixture(_ devices: [[String: Any]]) -> Data {
        let root: [String: Any] = ["info": [:], "result": ["devices": devices]]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    func testOnlyTunnelConnectedDevicesAreInstallTargets() {
        let json = fixture([
            [
                "identifier": "93A43638-0412-52DA-B201-AA8990C2313E",
                "deviceProperties": ["name": "Yam iPhone"],
                "hardwareProperties": ["udid": "00008120-001E30E11E78201E", "platform": "iOS", "marketingName": "iPhone 14 Pro"],
                "connectionProperties": ["pairingState": "paired", "tunnelState": "connected"],
            ],
            [
                "identifier": "380FDA4C-1424-5DB3-817B-3FFBEADD64F5",
                "deviceProperties": ["name": "Powered-off iPad"],
                "hardwareProperties": ["udid": "00008112-001438A811FA601E", "platform": "iOS", "marketingName": "iPad Air"],
                "connectionProperties": ["pairingState": "paired", "tunnelState": "unavailable"],
            ],
        ])

        let (connected, offline) = DeviceStore.parse(devicectlJSON: json)

        XCTAssertEqual(connected.count, 1)
        guard case .connectedDevice(let id, let name)? = connected.first else {
            return XCTFail("expected a connected device")
        }
        XCTAssertEqual(id, "00008120-001E30E11E78201E")
        XCTAssertEqual(name, "Yam iPhone")

        // The unreachable device is reported separately, never as a target.
        XCTAssertEqual(offline.map(\.id), ["00008112-001438A811FA601E"])
    }

    func testMalformedJSONYieldsNoDevices() {
        let (connected, offline) = DeviceStore.parse(devicectlJSON: Data("not json".utf8))
        XCTAssertTrue(connected.isEmpty)
        XCTAssertTrue(offline.isEmpty)
    }
}

final class SchedulerKeyTests: XCTestCase {
    func testEveryNDaysUsesStartInterval() {
        var s = AppSettings()
        s.scheduleFrequency = .everyNDays
        s.scheduledBuildIntervalDays = 6
        let keys = SchedulerService.schedulingKeys(for: s)
        XCTAssertEqual(keys["StartInterval"] as? Int, 6 * 86_400)
        XCTAssertNil(keys["StartCalendarInterval"])
    }

    func testDailyUsesCalendarIntervalAtTime() {
        var s = AppSettings()
        s.scheduleFrequency = .daily
        s.scheduleHour = 9
        s.scheduleMinute = 30
        let keys = SchedulerService.schedulingKeys(for: s)
        let cal = keys["StartCalendarInterval"] as? [String: Int]
        XCTAssertEqual(cal?["Hour"], 9)
        XCTAssertEqual(cal?["Minute"], 30)
        XCTAssertNil(cal?["Weekday"])
        XCTAssertNil(keys["StartInterval"])
    }

    func testWeeklyEmitsOneEntryPerWeekdayAtTime() {
        var s = AppSettings()
        s.scheduleFrequency = .weekly
        s.scheduleWeekdays = [4, 1] // Thu, Mon (unsorted on purpose)
        s.scheduleHour = 22
        s.scheduleMinute = 15
        let keys = SchedulerService.schedulingKeys(for: s)
        let entries = keys["StartCalendarInterval"] as? [[String: Int]]
        XCTAssertEqual(entries?.count, 2)
        XCTAssertEqual(entries?.map { $0["Weekday"] }, [1, 4]) // sorted
        XCTAssertTrue(entries?.allSatisfy { $0["Hour"] == 22 && $0["Minute"] == 15 } ?? false)
    }

    func testOutOfRangeTimeIsClamped() {
        var s = AppSettings()
        s.scheduleFrequency = .daily
        s.scheduleHour = 99
        s.scheduleMinute = -5
        let cal = SchedulerService.schedulingKeys(for: s)["StartCalendarInterval"] as? [String: Int]
        XCTAssertEqual(cal?["Hour"], 23)
        XCTAssertEqual(cal?["Minute"], 0)
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
