import AppKit
import SwiftUI
import UserNotifications

/// Handles notification authorization, foreground banners, and the
/// close-to-background (menu-bar-only) behavior.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NotificationService.requestAuthorization()

        // When the main window closes, keep running as a menu-bar-only app
        // (no Dock icon, not in ⌘-Tab) so scheduled builds and the menu bar
        // stay available. Reopening from the menu restores the Dock icon.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    /// Don't quit when the last window is closed — the app lives in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Window notifications post on the main thread; `@MainActor` lets us read
    // the window's (main-actor-isolated) identifier/title.
    @MainActor @objc private func mainWindowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow,
              window.identifier?.rawValue == "main" || window.title == "iOS Build Manager"
        else { return }
        // Defer until the close completes, then drop the Dock icon.
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Brings the app back to a normal foreground app (Dock icon + window) — call
/// before opening the main window from the menu bar.
@MainActor
func activateAsRegularApp() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
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
        Window(model.settings.settings.appDisplayName, id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.projects)
                .environmentObject(model.history)
                .environmentObject(model.devices)
                .environmentObject(model.engine)
                .environmentObject(model.profiles)
                .environmentObject(model.certificates)
                .environmentObject(model.branding)
                .environmentObject(model.github)
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
                .environmentObject(model.branding)
                .environmentObject(model.github)
        } label: {
            // A custom logo renders in colour at glyph size; without one this
            // is a template symbol sized like a native status item, since the
            // SwiftUI `systemImage` convenience renders too large and sits off
            // the menu bar's vertical center.
            Image(nsImage: model.branding.menuBarImage(fallbackSymbol: "shippingbox.fill"))
        }
        .menuBarExtraStyle(.window)
    }
}
