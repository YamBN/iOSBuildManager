import XCTest
@testable import iOSBuildManager

final class IPAPackagerTests: XCTestCase {
    func testPackCreatesVersionedIPAAndLatest() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("ipa-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }

        // Fake built .app bundle.
        let appDir = tmp.appendingPathComponent("Demo.app", isDirectory: true)
        try fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        try Data("fake binary".utf8).write(to: appDir.appendingPathComponent("Demo"))

        let output = tmp.appendingPathComponent("out", isDirectory: true)
        let ipa = try await IPAPackager.pack(
            appURL: appDir,
            appName: "Demo",
            version: "1.2.3",
            buildNumber: "45",
            outputFolder: output,
            keepLatest: true
        )

        XCTAssertEqual(ipa.lastPathComponent, "Demo-1.2.3-45.ipa")
        XCTAssertTrue(fm.fileExists(atPath: ipa.path))
        XCTAssertGreaterThan(IPAPackager.fileSize(at: ipa), 0)
        XCTAssertTrue(fm.fileExists(atPath: output.appendingPathComponent("latest.ipa").path))
    }

    func testSpacesInAppNameAreSanitized() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("ipa-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }

        let appDir = tmp.appendingPathComponent("My App.app", isDirectory: true)
        try fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: appDir.appendingPathComponent("My App"))

        let output = tmp.appendingPathComponent("out", isDirectory: true)
        let ipa = try await IPAPackager.pack(
            appURL: appDir,
            appName: "My App",
            version: "1.0",
            buildNumber: "1",
            outputFolder: output,
            keepLatest: false
        )

        XCTAssertEqual(ipa.lastPathComponent, "My_App-1.0-1.ipa")
        XCTAssertFalse(fm.fileExists(atPath: output.appendingPathComponent("latest.ipa").path))
    }
}
