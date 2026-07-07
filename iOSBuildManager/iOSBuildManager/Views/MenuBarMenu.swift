import AppKit
import SwiftUI

/// The status-bar menu shown from the menu bar icon. The app keeps running
/// after the main window closes, so this is the always-available surface for
/// the most common actions.
struct MenuBarMenu: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var engine: BuildEngine
    @EnvironmentObject private var history: BuildHistoryStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    private var quickBuildProject: Project? {
        model.selectedProject ?? model.projects.projects.first
    }

    var body: some View {
        statusLine

        Divider()

        Button("Open iOS Build Manager") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        if engine.isBuilding {
            Button("Cancel Build") { engine.cancel() }
        } else {
            Button("Build Now") {
                if let project = quickBuildProject {
                    model.startBuild(for: project.id)
                }
            }
            .disabled(quickBuildProject == nil)
        }

        Divider()

        Button("Reveal latest.ipa") {
            FinderActions.reveal(settings.settings.outputURL.appendingPathComponent("latest.ipa"))
        }
        Button("Open Builds Folder") {
            FinderActions.openFolder(settings.settings.outputURL)
        }

        Divider()

        Button("Quit iOS Build Manager") {
            NSApplication.shared.terminate(nil)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if engine.isBuilding {
            Text("Building \(engine.currentProjectName ?? "")…")
        } else if let last = history.mostRecent {
            Text("\(last.status == .success ? "✅" : "❌") \(last.projectName) \(last.version) (\(last.buildNumber)) — \(last.date.formatted(date: .abbreviated, time: .shortened))")
        } else {
            Text("No builds yet")
        }
    }
}
