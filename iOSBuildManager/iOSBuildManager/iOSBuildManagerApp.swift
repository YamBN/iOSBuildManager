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
        WindowGroup {
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
    }
}
