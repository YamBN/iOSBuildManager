import AppKit
import SwiftUI
import UserNotifications

/// Handles notification authorization and lets banners show while the app is
/// frontmost (macOS suppresses them by default otherwise).
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NotificationService.requestAuthorization()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
@MainActor
struct iOSBuildManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        // A single identified Window (not a WindowGroup) so the menu bar item
        // can reopen it after the user closes it. Closing the window does not
        // quit the app — it keeps running for scheduled builds and the menu bar.
        Window("iOS Build Manager", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.projects)
                .environmentObject(model.history)
                .environmentObject(model.devices)
                .environmentObject(model.engine)
                .environmentObject(model.profiles)
                .environmentObject(model.certificates)
                .preferredColorScheme(model.settings.settings.theme.colorScheme)
                .frame(minWidth: 1040, minHeight: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Project…") { model.selection = .settings }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Build Selected Project") {
                    if let id = model.selectedProjectId { model.startBuild(for: id) }
                }
                .keyboardShortcut("b", modifiers: .command)
            }
        }

        MenuBarExtra(
            isInserted: Binding(
                get: { model.settings.settings.showMenuBarIcon },
                set: { model.settings.settings.showMenuBarIcon = $0 }
            )
        ) {
            MenuBarMenu()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.projects)
                .environmentObject(model.history)
                .environmentObject(model.devices)
                .environmentObject(model.engine)
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    /// A template NSImage sized like a native status item glyph — the SwiftUI
    /// `systemImage` convenience renders too large and sits off the menu bar's
    /// vertical center.
    private static let menuBarIcon: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(
            systemSymbolName: "shippingbox.fill",
            accessibilityDescription: "iOS Build Manager"
        )?.withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        return image
    }()
}
