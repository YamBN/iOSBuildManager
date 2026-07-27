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

final class UpdateCheckTests: XCTestCase {
    func testNormalizeStripsLeadingV() {
        XCTAssertEqual(UpdateCheckService.normalize("v1.2.0"), "1.2.0")
        XCTAssertEqual(UpdateCheckService.normalize("1.2.0"), "1.2.0")
    }

    func testNewerPatchVersionDetected() {
        XCTAssertTrue(UpdateCheckService.isNewer("1.1.1", than: "1.1.0"))
    }

    func testNewerMinorVersionDetected() {
        XCTAssertTrue(UpdateCheckService.isNewer("1.2.0", than: "1.1.9"))
    }

    func testSameVersionIsNotNewer() {
        XCTAssertFalse(UpdateCheckService.isNewer("1.1.0", than: "1.1.0"))
    }

    func testOlderVersionIsNotNewer() {
        XCTAssertFalse(UpdateCheckService.isNewer("1.0.0", than: "1.1.0"))
    }

    /// Numeric comparison, not lexical — "1.10.0" must beat "1.9.0" even
    /// though "1.10.0" < "1.9.0" as a string.
    func testDoubleDigitComponentComparesNumerically() {
        XCTAssertTrue(UpdateCheckService.isNewer("1.10.0", than: "1.9.0"))
        XCTAssertFalse(UpdateCheckService.isNewer("1.9.0", than: "1.10.0"))
    }

    func testMissingComponentsTreatedAsZero() {
        XCTAssertTrue(UpdateCheckService.isNewer("1.1", than: "1.0.9"))
        XCTAssertFalse(UpdateCheckService.isNewer("1.0", than: "1.0.0"))
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

final class PlatformDetectionTests: XCTestCase {
    func testDetectsIOSFromSupportedPlatforms() {
        let lines = ["    SDKROOT = iphoneos", "    SUPPORTED_PLATFORMS = iphoneos iphonesimulator"]
        XCTAssertEqual(XcodeBuildService.parsePlatform(fromBuildSettings: lines), .iOS)
    }

    func testDetectsMacFromSupportedPlatforms() {
        let lines = ["    SUPPORTED_PLATFORMS = macosx", "    PLATFORM_NAME = macosx"]
        XCTAssertEqual(XcodeBuildService.parsePlatform(fromBuildSettings: lines), .macOS)
    }

    func testIOSWinsWhenBothSupported() {
        // Mac Catalyst targets list both; this app's job is iOS, so iOS wins.
        let lines = ["    SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx"]
        XCTAssertEqual(XcodeBuildService.parsePlatform(fromBuildSettings: lines), .iOS)
    }

    func testUnknownWhenNoPlatformKeys() {
        XCTAssertEqual(XcodeBuildService.parsePlatform(fromBuildSettings: ["    PRODUCT_NAME = Foo"]), .unknown)
    }

    func testIgnoresKeysThatMerelyContainThePrefix() {
        // A line like OTHER_SUPPORTED_PLATFORMS_X must not be mistaken for the key.
        let lines = ["    SUPPORTED_PLATFORMS_EXTRA = macosx", "    SDKROOT = iphoneos"]
        XCTAssertEqual(XcodeBuildService.parsePlatform(fromBuildSettings: lines), .iOS)
    }
}

final class ExportFormatTests: XCTestCase {
    func testMacFormatsDefaultToDMGFirst() {
        XCTAssertEqual(ExportFormat.formats(for: .macOS), [.dmg, .appZip])
    }

    func testIOSFormatsAreIPAOnly() {
        XCTAssertEqual(ExportFormat.formats(for: .iOS), [.ipa])
        XCTAssertEqual(ExportFormat.formats(for: .unknown), [.ipa])
    }

    func testResolvedExportFormatFallsBackToPlatformDefault() {
        var project = Project(name: "Mac", path: "/tmp/Mac.xcodeproj", isWorkspace: false)
        project.detectedPlatform = .macOS
        // No explicit choice → platform default (DMG).
        XCTAssertEqual(project.resolvedExportFormat, .dmg)
        // An iOS-only format on a mac project is ignored in favour of the default.
        project.exportFormat = .ipa
        XCTAssertEqual(project.resolvedExportFormat, .dmg)
        // A valid choice is honoured.
        project.exportFormat = .appZip
        XCTAssertEqual(project.resolvedExportFormat, .appZip)
    }
}

final class BrandingNormalizationTests: XCTestCase {
    private func solidImage(width: CGFloat, height: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    func testWideImageIsNormalizedToSquare() throws {
        let normalized = try XCTUnwrap(BrandingStore.normalized(solidImage(width: 400, height: 100), size: 256))
        XCTAssertEqual(normalized.size.width, 256)
        XCTAssertEqual(normalized.size.height, 256)
    }

    func testTallImageIsNormalizedToSquare() throws {
        let normalized = try XCTUnwrap(BrandingStore.normalized(solidImage(width: 60, height: 500), size: 256))
        XCTAssertEqual(normalized.size.width, 256)
        XCTAssertEqual(normalized.size.height, 256)
    }

    func testProducesPNGData() throws {
        let data = try XCTUnwrap(BrandingStore.normalizedPNGData(from: solidImage(width: 120, height: 80), size: 128))
        XCTAssertFalse(data.isEmpty)
        // PNG magic number.
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testZeroSizedImageIsRejected() {
        XCTAssertNil(BrandingStore.normalized(NSImage(size: .zero), size: 256))
    }

    func testRendersAtAnExactPixelSize() throws {
        let data = try XCTUnwrap(BrandingStore.pngData(from: solidImage(width: 300, height: 300), pixelSize: 64))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, 64)
        XCTAssertEqual(rep.pixelsHigh, 64)
    }

    func testProjectDisplayNameUsesOverride() {
        var project = Project(name: "RawName", path: "/tmp/X.xcodeproj", isWorkspace: false)
        XCTAssertEqual(project.displayName, "RawName")
        project.displayNameOverride = "  "
        XCTAssertEqual(project.displayName, "RawName")
        project.displayNameOverride = "Pretty Name"
        XCTAssertEqual(project.displayName, "Pretty Name")
    }
}

@MainActor
final class MenuBarProgressIconTests: XCTestCase {
    func testIsATemplateSoTheMenuBarCanTintIt() {
        XCTAssertTrue(iOSBuildManagerApp.buildingIcon(percent: 50).isTemplate)
    }

    func testWidthGrowsWithTheNumberOfDigits() {
        let one = iOSBuildManagerApp.buildingIcon(percent: 5).size.width
        let two = iOSBuildManagerApp.buildingIcon(percent: 50).size.width
        let three = iOSBuildManagerApp.buildingIcon(percent: 100).size.width
        XCTAssertLessThan(one, two)
        XCTAssertLessThan(two, three)
    }

    func testOutOfRangeValuesAreClampedToTheSameWidthAsTheBounds() {
        // Clamping keeps a bogus value from drawing a bar past the track.
        XCTAssertEqual(iOSBuildManagerApp.buildingIcon(percent: -20).size.width,
                       iOSBuildManagerApp.buildingIcon(percent: 0).size.width)
        XCTAssertEqual(iOSBuildManagerApp.buildingIcon(percent: 500).size.width,
                       iOSBuildManagerApp.buildingIcon(percent: 100).size.width)
    }

    func testHasANonZeroDrawnSize() {
        let icon = iOSBuildManagerApp.buildingIcon(percent: 42)
        XCTAssertGreaterThan(icon.size.width, 0)
        XCTAssertEqual(icon.size.height, 15)
    }
}

final class BuildBrandingTests: XCTestCase {
    private func makeBundle(isMac: Bool, iconNames: [String] = []) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("brand-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent("Test.app", isDirectory: true)
        let plistURL = BuildBrandingService.infoPlistURL(in: app, isMac: isMac)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleName": "Original", "CFBundleIconName": "AppIcon"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)

        for name in iconNames {
            let data = try XCTUnwrap(BrandingStore.pngData(from: NSImage(size: NSSize(width: 10, height: 10)), pixelSize: 60))
            try data.write(to: app.appendingPathComponent(name))
        }
        return app
    }

    func testMacInfoPlistLivesUnderContents() {
        let app = URL(fileURLWithPath: "/tmp/X.app")
        XCTAssertEqual(BuildBrandingService.infoPlistURL(in: app, isMac: true).lastPathComponent, "Info.plist")
        XCTAssertTrue(BuildBrandingService.infoPlistURL(in: app, isMac: true).path.contains("Contents"))
        XCTAssertFalse(BuildBrandingService.infoPlistURL(in: app, isMac: false).path.contains("Contents"))
    }

    func testFindsOnlyAppIconPNGsInBundle() throws {
        let app = try makeBundle(isMac: false, iconNames: ["AppIcon60x60@2x.png", "AppIcon76x76.png", "Launch.png"])
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let found = BuildBrandingService.iconFileURLs(in: app).map(\.lastPathComponent).sorted()
        XCTAssertEqual(found, ["AppIcon60x60@2x.png", "AppIcon76x76.png"])
    }

    func testReplacesIOSIconsKeepingTheirPixelSize() throws {
        let app = try makeBundle(isMac: false, iconNames: ["AppIcon60x60@2x.png"])
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let source = NSImage(size: NSSize(width: 400, height: 200))
        let replaced = try BuildBrandingService.applyIOSIcons(source, in: app)
        XCTAssertEqual(replaced, 1)
        // The file keeps the dimensions the bundle expected (60pt @2x = 120px…
        // here the fixture wrote 60px, so it must still be 60px).
        XCTAssertEqual(BuildBrandingService.pixelSize(of: app.appendingPathComponent("AppIcon60x60@2x.png")), 60)
    }

    func testICNSSlotsCoverEverySizeMacNeeds() {
        let sizes = Set(BuildBrandingService.icnsSlots.map(\.size))
        XCTAssertEqual(sizes, [16, 32, 64, 128, 256, 512, 1024])
        XCTAssertEqual(BuildBrandingService.icnsSlots.count, 10)
    }

    func testPlistRoundTrip() throws {
        let app = try makeBundle(isMac: true)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let url = BuildBrandingService.infoPlistURL(in: app, isMac: true)

        var plist = try XCTUnwrap(BuildBrandingService.readPlist(at: url))
        plist["CFBundleDisplayName"] = "Renamed"
        // CFBundleIconName wins over CFBundleIconFile on macOS, so applying a
        // custom icon must clear it.
        plist.removeValue(forKey: "CFBundleIconName")
        XCTAssertTrue(BuildBrandingService.writePlist(plist, to: url))

        let reread = try XCTUnwrap(BuildBrandingService.readPlist(at: url))
        XCTAssertEqual(reread["CFBundleDisplayName"] as? String, "Renamed")
        XCTAssertNil(reread["CFBundleIconName"])
    }

    func testNoOpWhenNothingIsCustomized() async throws {
        let app = try makeBundle(isMac: true)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let log = await BuildBrandingService.apply(iconURL: nil, displayName: "   ", to: app, isMac: true)
        XCTAssertTrue(log.isEmpty)
    }
}

final class GitHubAuthParsingTests: XCTestCase {
    func testParsesDeviceCodeResponse() throws {
        let json = """
        {"device_code":"abc123","user_code":"WXYZ-1234",
         "verification_uri":"https://github.com/login/device","expires_in":899,"interval":5}
        """
        let grant = try XCTUnwrap(GitHubAuthService.parseDeviceCode(Data(json.utf8)))
        XCTAssertEqual(grant.deviceCode, "abc123")
        XCTAssertEqual(grant.userCode, "WXYZ-1234")
        XCTAssertEqual(grant.interval, 5)
    }

    func testRejectsMalformedDeviceCodeResponse() {
        XCTAssertNil(GitHubAuthService.parseDeviceCode(Data(#"{"error":"bad_verification_code"}"#.utf8)))
    }

    func testPollStates() {
        XCTAssertEqual(GitHubAuthService.parsePoll(Data(#"{"access_token":"tok"}"#.utf8)), .token("tok"))
        XCTAssertEqual(GitHubAuthService.parsePoll(Data(#"{"error":"authorization_pending"}"#.utf8)), .pending)
        XCTAssertEqual(GitHubAuthService.parsePoll(Data(#"{"error":"slow_down"}"#.utf8)), .slowDown)
        XCTAssertEqual(GitHubAuthService.parsePoll(Data(#"{"error":"access_denied"}"#.utf8)), .denied)
        XCTAssertEqual(GitHubAuthService.parsePoll(Data(#"{"error":"expired_token"}"#.utf8)), .expired)
    }

    func testPollUnknownErrorSurfacesDescription() {
        let result = GitHubAuthService.parsePoll(Data(#"{"error":"nope","error_description":"Something broke"}"#.utf8))
        XCTAssertEqual(result, .failed("Something broke"))
    }
}

final class GitParsingTests: XCTestCase {
    func testParsesPorcelainStatus() {
        let lines = [" M Sources/App.swift", "?? New File.swift", "A  Added.swift", ""]
        XCTAssertEqual(GitService.parseChangedFiles(lines),
                       ["Sources/App.swift", "New File.swift", "Added.swift"])
    }

    func testRepoFullNameFromHTTPSRemote() {
        XCTAssertEqual(GitService.repoFullName(fromRemote: "https://github.com/YamBN/iOSBuildManager.git"),
                       "YamBN/iOSBuildManager")
    }

    func testRepoFullNameFromSSHRemote() {
        XCTAssertEqual(GitService.repoFullName(fromRemote: "git@github.com:YamBN/iOSBuildManager.git"),
                       "YamBN/iOSBuildManager")
    }

    func testRepoFullNameIgnoresNonGitHubRemote() {
        XCTAssertNil(GitService.repoFullName(fromRemote: "https://gitlab.com/foo/bar.git"))
    }

    func testAuthenticatedRemoteIsNeverStoredAsOrigin() {
        // The public remote must not carry the token.
        XCTAssertEqual(GitService.publicRemote(repoFullName: "o/r"), "https://github.com/o/r.git")
        XCTAssertFalse(GitService.publicRemote(repoFullName: "o/r").contains("x-access-token"))
        XCTAssertTrue(GitService.authenticatedRemote(repoFullName: "o/r", token: "secret").contains("secret"))
    }

    func testRedactionRemovesSecrets() {
        let text = "fatal: repo https://x-access-token:ghp_SECRET@github.com/o/r.git not found"
        let redacted = GitService.redact(text, secrets: ["ghp_SECRET"])
        XCTAssertFalse(redacted.contains("ghp_SECRET"))
        XCTAssertTrue(redacted.contains("***"))
    }
}

final class GitHubAPIParsingTests: XCTestCase {
    func testParsesRepositories() {
        let json = """
        [{"id":1,"full_name":"o/r","html_url":"https://github.com/o/r","private":true,"default_branch":"main"}]
        """
        let repos = GitHubService.parseRepos(Data(json.utf8))
        XCTAssertEqual(repos.count, 1)
        XCTAssertEqual(repos.first?.fullName, "o/r")
        XCTAssertTrue(repos.first?.isPrivate ?? false)
    }

    func testParsesWorkflowRuns() {
        let json = """
        {"workflow_runs":[
          {"id":7,"name":"CI","status":"completed","conclusion":"success","head_branch":"main",
           "html_url":"https://github.com/o/r/actions/runs/7","created_at":"2026-07-12T10:00:00Z"}
        ]}
        """
        let runs = GitHubService.parseWorkflowRuns(Data(json.utf8))
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.displayState, "success")
        XCTAssertEqual(runs.first?.systemImage, "checkmark.circle.fill")
    }

    func testRunStillGoingUsesStatusAsDisplayState() {
        let json = #"{"workflow_runs":[{"id":8,"name":"CI","status":"in_progress","head_branch":"main"}]}"#
        let runs = GitHubService.parseWorkflowRuns(Data(json.utf8))
        XCTAssertEqual(runs.first?.displayState, "in_progress")
    }
}

final class AppInfoReadTests: XCTestCase {
    private func makeApp(plistAt relativePath: String) throws -> URL {
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-\(UUID().uuidString)/Test.app", isDirectory: true)
        let plistURL = app.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": "2.5", "CFBundleVersion": "7"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
        return app
    }

    func testReadsRootInfoPlist_iOSLayout() throws {
        let app = try makeApp(plistAt: "Info.plist")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let info = try XcodeBuildService.readAppInfo(at: app)
        XCTAssertEqual(info.version, "2.5")
        XCTAssertEqual(info.buildNumber, "7")
    }

    func testReadsContentsInfoPlist_macLayout() throws {
        let app = try makeApp(plistAt: "Contents/Info.plist")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let info = try XcodeBuildService.readAppInfo(at: app)
        XCTAssertEqual(info.version, "2.5")
        XCTAssertEqual(info.buildNumber, "7")
    }

    func testThrowsWhenNoPlistAnywhere() {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)/X.app")
        XCTAssertThrowsError(try XcodeBuildService.readAppInfo(at: app))
    }
}

final class SwiftPackageTests: XCTestCase {
    func testParsesExecutableProductsOnly() {
        let json = """
        {
          "products": [
            { "name": "MyLib", "type": { "library": ["automatic"] } },
            { "name": "MyApp", "type": { "executable": null } },
            { "name": "MyTool", "type": { "executable": null } }
          ]
        }
        """
        let names = SwiftPackageService.parseExecutableProducts(dumpPackageJSON: Data(json.utf8))
        XCTAssertEqual(names, ["MyApp", "MyTool"])
    }

    func testNoExecutableProducts() {
        let json = #"{ "products": [ { "name": "OnlyLib", "type": { "library": ["automatic"] } } ] }"#
        XCTAssertEqual(SwiftPackageService.parseExecutableProducts(dumpPackageJSON: Data(json.utf8)), [])
    }

    func testMalformedJSONYieldsEmpty() {
        XCTAssertEqual(SwiftPackageService.parseExecutableProducts(dumpPackageJSON: Data("not json".utf8)), [])
    }

    func testSwiftBuildArgumentsMapConfiguration() {
        XCTAssertEqual(SwiftPackageService.buildArguments(product: "App", configuration: .release),
                       ["build", "-c", "release", "--product", "App"])
        XCTAssertEqual(SwiftPackageService.buildArguments(product: nil, configuration: .debug),
                       ["build", "-c", "debug"])
    }
}

final class BuildProgressEstimatorTests: XCTestCase {
    func testExpectedDurationIsNilWithNoHistory() {
        XCTAssertNil(BuildProgressEstimator.expectedDuration(from: []))
    }

    func testExpectedDurationIsMeanOfDurations() {
        XCTAssertEqual(BuildProgressEstimator.expectedDuration(from: [10, 20, 30]), 20)
    }

    func testProgressIsNilWithoutExpectedDuration() {
        XCTAssertNil(BuildProgressEstimator.progress(elapsed: 10, expected: nil))
        XCTAssertNil(BuildProgressEstimator.progress(elapsed: 10, expected: 0))
    }

    func testProgressScalesWithElapsedTime() {
        XCTAssertEqual(BuildProgressEstimator.progress(elapsed: 30, expected: 60), 0.5)
    }

    func testProgressIsCappedShortOfComplete() {
        XCTAssertEqual(BuildProgressEstimator.progress(elapsed: 1000, expected: 60), 0.95)
    }

    func testProgressNeverGoesNegative() {
        XCTAssertEqual(BuildProgressEstimator.progress(elapsed: -5, expected: 60), 0)
    }

    func testFormattedElapsedPadsSeconds() {
        XCTAssertEqual(BuildProgressEstimator.formattedElapsed(65), "1:05")
        XCTAssertEqual(BuildProgressEstimator.formattedElapsed(5), "0:05")
        XCTAssertEqual(BuildProgressEstimator.formattedElapsed(-3), "0:00")
    }
}
