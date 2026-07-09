import SwiftUI

/// Root two-column layout: glass sidebar + selected section.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $model.selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
                .background(AppBackground())
        } detail: {
            detailView
                .navigationSplitViewColumnWidth(min: 640, ideal: 900)
                .background(AppBackground())
        }
        .background(AppBackground())
        .task { await model.checkForUpdates() }
        .sheet(item: $model.availableUpdate) { update in
            UpdateAvailableSheet(update: update)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch model.selection {
        case .dashboard: DashboardView()
        case .builds: BuildsView()
        case .profiles: ProfilesView()
        case .certificates: CertificatesView()
        case .devices: DevicesView()
        case .settings: SettingsView()
        case .logs: LogsView()
        }
    }
}
