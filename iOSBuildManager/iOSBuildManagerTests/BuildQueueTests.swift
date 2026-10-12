import XCTest
@testable import iOSBuildManager

@MainActor
final class BuildQueueTests: XCTestCase {
    private func fixture() throws -> (URL, BuildQueue) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let queue = BuildQueue(directory: root)
        queue.resolve = { request in
            (Project(name: request.scheme ?? "Fixture", path: "/tmp/Fixture.xcodeproj", isWorkspace: false), AppSettings())
        }
        queue.start(poll: false)
        XCTAssertNil(queue.lastError)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, queue)
    }

    func testSerialDispatchPersistsBeforeRunAndContinuesAfterFailure() throws {
        let (root, queue) = try fixture()
        var launched: [UUID] = []
        queue.run = { job in
            let saved = try? JSONDecoder().decode(BuildQueueState.self,
                from: Data(contentsOf: root.appendingPathComponent("state.json")))
            XCTAssertEqual(saved?.jobs.first(where: { $0.id == job.id })?.state, "running")
            launched.append(job.id)
        }
        let first = BuildRequest(scheme: "One")
        let second = BuildRequest(scheme: "Two")
        try queue.submit(first)
        queue.tick()
        try queue.submit(second)
        queue.tick()
        XCTAssertEqual(launched, [first.id])
        XCTAssertEqual(queue.pendingCount, 1)
        queue.complete(state: "failed", error: "Build failed")
        queue.tick()
        XCTAssertEqual(launched, [first.id, second.id])
        queue.complete(state: "succeeded", artifactPath: "/tmp/Two.ipa")
        XCTAssertEqual(queue.state.jobs.last?.artifactPath, "/tmp/Two.ipa")
    }

    func testDuplicatePublicationDoesNotRepeatBuild() throws {
        let (_, queue) = try fixture()
        var runs = 0
        queue.run = { _ in runs += 1 }
        let request = BuildRequest()
        try queue.submit(request)
        queue.tick()
        queue.complete(state: "succeeded")
        try queue.submit(request)
        queue.tick()
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(queue.state.jobs.count, 1)
    }

    func testSecondWorkerCannotConsumeCommands() throws {
        let (root, first) = try fixture()
        let second = BuildQueue(directory: root)
        second.start(poll: false)
        XCTAssertTrue(first.ownsWorker)
        XCTAssertFalse(second.ownsWorker)
        XCTAssertNotNil(second.lastError)
    }

    func testCrashRecoveryPausesUntilExplicitResume() throws {
        let (root, queue) = try fixture()
        let interrupted = QueuedBuild(request: BuildRequest(), state: "running")
        let pending = QueuedBuild(request: BuildRequest(),
            project: Project(name: "Pending", path: "/tmp/P.xcodeproj", isWorkspace: false), settings: AppSettings())
        let otherRoot = root.appendingPathComponent("recovery")
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        try JSONEncoder().encode(BuildQueueState(jobs: [interrupted, pending]))
            .write(to: otherRoot.appendingPathComponent("state.json"))
        let recovered = BuildQueue(directory: otherRoot)
        var runs = 0
        recovered.run = { _ in runs += 1 }
        recovered.start(poll: false)
        recovered.tick()
        XCTAssertTrue(recovered.state.paused)
        XCTAssertEqual(recovered.state.jobs[0].state, "interrupted")
        XCTAssertEqual(runs, 0)
        try recovered.submit(BuildRequest(action: "resume"))
        recovered.tick()
        XCTAssertEqual(runs, 1)
        XCTAssertTrue(queue.ownsWorker)
    }

    func testQueuedCancellationAndMalformedRequestDoNotBlockLaterWork() throws {
        let (_, queue) = try fixture()
        queue.run = { _ in }
        try queue.submit(BuildRequest())
        queue.tick()
        let pending = BuildRequest()
        try queue.submit(pending)
        queue.tick()
        try queue.submit(BuildRequest(action: "cancel", targetId: pending.id))
        let invalidID = UUID()
        try Data("broken".utf8).write(to: queue.inbox.appendingPathComponent(invalidID.uuidString + ".json"))
        queue.tick()
        XCTAssertEqual(queue.state.jobs.first(where: { $0.id == pending.id })?.state, "cancelled")
        XCTAssertEqual(queue.state.jobs.first(where: { $0.id == invalidID })?.state, "rejected")
        queue.complete(state: "failed")
        queue.tick()
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testCorruptStateFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.json")
        try Data("broken".utf8).write(to: url)
        let queue = BuildQueue(directory: root)
        queue.start(poll: false)
        queue.tick()
        XCTAssertNotNil(queue.lastError)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "broken")
    }

    func testPersistenceFailureDoesNotDispatch() throws {
        let (root, queue) = try fixture()
        var runs = 0
        queue.run = { _ in runs += 1 }
        try queue.submit(BuildRequest())
        let stateURL = root.appendingPathComponent("state.json")
        try FileManager.default.removeItem(at: stateURL)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: false)
        queue.tick()
        XCTAssertEqual(runs, 0)
        XCTAssertNotNil(queue.lastError)
    }

    func testSchedulerSubmitsToCLIInsteadOfLaunchingXcode() {
        let project = Project(name: "A '$ Project", path: "/tmp/A.xcodeproj", isWorkspace: false)
        let script = ScriptGenerator.generateScheduledBuildScript(for: project)
        XCTAssertTrue(script.contains("enqueue --project-id"))
        XCTAssertTrue(script.contains(project.id.uuidString))
        XCTAssertTrue(script.contains("--install-on-device"))
        XCTAssertFalse(script.contains("/usr/bin/xcodebuild"))
    }
    /// Real local chain: bundled Python CLI -> durable inbox -> AppModel ->
    /// xcodebuild -> BuildEngine -> IPAPackager -> JSON receipt. No signing,
    /// network dependencies, iCloud output, device install or UI automation.
    func testCLIThroughRealBuildEngineProducesIsolatedIPAsAfterFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("queue-e2e-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectURL = root.appendingPathComponent("Fixture.xcodeproj")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try "int main(void) { return 0; }".write(to: root.appendingPathComponent("main.c"), atomically: true, encoding: .utf8)
        let pbx = """
        { archiveVersion = 1; objectVersion = 56; objects = {
          A00000000000000000000001 = { isa = PBXProject; mainGroup = A00000000000000000000002;
            buildConfigurationList = A00000000000000000000008; compatibilityVersion = "Xcode 14.0";
            targets = (A00000000000000000000003); };
          A00000000000000000000002 = { isa = PBXGroup; sourceTree = "<group>";
            children = (A00000000000000000000004, A00000000000000000000005); };
          A00000000000000000000003 = { isa = PBXNativeTarget; name = Fixture;
            buildConfigurationList = A00000000000000000000009;
            buildPhases = (A00000000000000000000006); productReference = A00000000000000000000005;
            productType = "com.apple.product-type.application"; };
          A00000000000000000000004 = { isa = PBXFileReference; path = main.c; sourceTree = "<group>"; lastKnownFileType = sourcecode.c.c; };
          A00000000000000000000005 = { isa = PBXFileReference; path = Fixture.app; sourceTree = BUILT_PRODUCTS_DIR; explicitFileType = wrapper.application; };
          A00000000000000000000006 = { isa = PBXSourcesBuildPhase; files = (A00000000000000000000007); };
          A00000000000000000000007 = { isa = PBXBuildFile; fileRef = A00000000000000000000004; };
          A00000000000000000000008 = { isa = XCConfigurationList; buildConfigurations = (A0000000000000000000000A); defaultConfigurationName = Release; };
          A00000000000000000000009 = { isa = XCConfigurationList; buildConfigurations = (A0000000000000000000000B); defaultConfigurationName = Release; };
          A0000000000000000000000A = { isa = XCBuildConfiguration; name = Release; buildSettings = { SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 15.0; }; };
          A0000000000000000000000B = { isa = XCBuildConfiguration; name = Release; buildSettings = {
            PRODUCT_NAME = Fixture; PRODUCT_BUNDLE_IDENTIFIER = "local.queue.fixture";
            CODE_SIGNING_ALLOWED = NO; GENERATE_INFOPLIST_FILE = YES;
            MARKETING_VERSION = 1.0; CURRENT_PROJECT_VERSION = 1; TARGETED_DEVICE_FAMILY = "1,2";
          }; };
        }; rootObject = A00000000000000000000001; }
        """
        try pbx.write(to: projectURL.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
        let secondProjectURL = root.appendingPathComponent("Second.xcodeproj")
        try FileManager.default.copyItem(at: projectURL, to: secondProjectURL)
        let model = AppModel()
        model.settings.settings.notifyOnBuildComplete = false
        let cli = try XCTUnwrap(Bundle.main.url(forResource: "iosbuild", withExtension: "py"))
        var ids: [UUID] = []
        for (index, scheme) in ["MissingScheme", "Fixture", "Fixture"].enumerated() {
            let lines = try await ShellRunner.collect(command: "/usr/bin/python3", arguments: [
                cli.path, "--support-dir", AppPaths.supportURL.path, "--no-launch", "enqueue",
                "--project", (index == 2 ? secondProjectURL : projectURL).path, "--scheme", scheme, "--output", root.appendingPathComponent("output").path
            ])
            let data = Data(lines.joined(separator: "\n").utf8)
            let response = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
            ids.append(try XCTUnwrap(UUID(uuidString: try XCTUnwrap(response["id"]))))
        }
        model.buildQueue.start(poll: false)
        var sawCLIProgress = false
        var sawWaitingBadge = false
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            model.buildQueue.tick()
            sawCLIProgress = sawCLIProgress || model.buildPercent != nil
            sawWaitingBadge = sawWaitingBadge || model.buildQueue.pendingCount > 0
            let jobs = model.buildQueue.state.jobs.filter { ids.contains($0.id) }
            if jobs.count == 3 && jobs.allSatisfy({ ["failed", "succeeded", "rejected"].contains($0.state) }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let jobs = ids.compactMap { id in model.buildQueue.state.jobs.first { $0.id == id } }
        XCTAssertEqual(jobs.map(\.state), ["failed", "succeeded", "succeeded"], model.engine.lastError ?? "")
        XCTAssertTrue(sawCLIProgress, "CLI builds must feed the same menu-bar progress as manual builds")
        XCTAssertTrue(sawWaitingBadge, "Pending CLI jobs must feed the menu-bar waiting count")
        let paths = jobs.compactMap(\.artifactPath)
        XCTAssertEqual(Set(paths).count, 2)
        for path in paths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path))
            let contents = try await ShellRunner.collect(command: "/usr/bin/unzip", arguments: ["-Z1", path])
            XCTAssertTrue(contents.contains("Payload/Fixture.app/Fixture"))
        }
    }

}
