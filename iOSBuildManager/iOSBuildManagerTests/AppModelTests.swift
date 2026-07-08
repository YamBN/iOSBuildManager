import Combine
import XCTest
@testable import iOSBuildManager

@MainActor
final class AppModelTests: XCTestCase {
    /// The App scene reads `model.settings.settings.theme` for
    /// `preferredColorScheme`; if AppModel stops forwarding the settings
    /// store's change events, the theme picker silently does nothing.
    func testSettingsChangesAreForwardedToAppModel() {
        let model = AppModel()
        let expectation = expectation(description: "objectWillChange forwarded")
        // Both the change and the restore below emit events; one is enough.
        expectation.assertForOverFulfill = false
        var cancellables: Set<AnyCancellable> = []

        model.objectWillChange
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        let original = model.settings.settings.theme
        model.settings.settings.theme = original == .dark ? .light : .dark

        wait(for: [expectation], timeout: 1)

        // Restore so the test doesn't flip the developer's persisted theme.
        model.settings.settings.theme = original
    }

    /// SwiftUI's MenuBarExtra rewrites its isInserted binding with the same
    /// value on every scene update. If a no-op settings write publishes, the
    /// scene re-evaluates forever (100% CPU). This pins the equality guard.
    func testNoOpSettingsWriteDoesNotPublish() {
        let store = SettingsStore()
        var events = 0
        var cancellables: Set<AnyCancellable> = []

        store.objectWillChange
            .sink { _ in events += 1 }
            .store(in: &cancellables)

        let current = store.settings
        store.settings = current

        XCTAssertEqual(events, 0, "assigning an unchanged AppSettings must not publish")
    }
}
