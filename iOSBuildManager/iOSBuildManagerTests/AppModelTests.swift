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
}
