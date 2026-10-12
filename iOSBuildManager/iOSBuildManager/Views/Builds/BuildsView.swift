import SwiftUI

struct BuildsView: View {
    @EnvironmentObject private var history: BuildHistoryStore
    @EnvironmentObject private var model: AppModel

    @State private var search: String = ""

    private var filtered: [BuildRecord] {
        guard !search.isEmpty else { return history.builds }
        let q = search.lowercased()
        return history.builds.filter {
            $0.projectName.lowercased().contains(q) ||
            $0.version.lowercased().contains(q) ||
            $0.outputURL.lastPathComponent.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = model.buildQueue.lastError {
                Text(error).foregroundStyle(.red).padding(8)
            }
            if model.buildQueue.state.paused {
                Text("Queue paused after an interrupted build. Check for active build processes, then use the CLI resume command.")
                    .foregroundStyle(.orange).padding(8)
            }
            if model.buildQueue.pendingCount > 0 {
                Text("\(model.buildQueue.pendingCount) build(s) waiting in the queue")
                    .font(.callout).padding(8)
            }
            queueSummary
            Divider()
            list
        }
        .navigationTitle("Builds")
        .searchable(text: $search, placement: .toolbar, prompt: "Search builds")
    }

    @ViewBuilder
    private var queueSummary: some View {
        let jobs = model.buildQueue.state.jobs.filter { $0.request.action == "enqueue" }.suffix(5)
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent queue requests").font(.caption.weight(.semibold))
                ForEach(Array(jobs.reversed())) { job in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.project?.name ?? job.request.scheme ?? "Build request")
                            if let error = job.error {
                                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                            }
                        }
                        Spacer()
                        Text(job.state.capitalized).foregroundStyle(.secondary)
                        if let path = job.artifactPath {
                            Button("Reveal") { FinderActions.reveal(URL(fileURLWithPath: path)) }
                        }
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(history.builds.count) build(s)")
                    .font(.headline)
                Text("Tap a row to reveal it in Finder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                history.clear()
            } label: {
                Label("Clear History", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(history.builds.isEmpty)
        }
        .padding(16)
    }

    private var columnHeader: some View {
        HStack {
            Text("").frame(width: 24)
            Text("Project / Version").frame(maxWidth: .infinity, alignment: .leading)
            Text("Date").frame(width: 150, alignment: .leading)
            Text("Size").frame(width: 80, alignment: .leading)
            Text("Status").frame(width: 90, alignment: .leading)
            Text("").frame(width: 60)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var list: some View {
        if filtered.isEmpty {
            EmptyStateView(
                title: search.isEmpty ? "No Builds Yet" : "No Matches",
                systemImage: "hammer",
                description: Text(search.isEmpty ? "Build a project to populate history." : "Try a different search.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            columnHeader
            Divider()
            List {
                ForEach(filtered) { build in
                    BuildRow(build: build)
                        .contextMenu { contextMenu(for: build) }
                        .swipeActions {
                            Button(role: .destructive) {
                                history.remove(build, deleteFile: false)
                            } label: { Label("Remove", systemImage: "trash") }
                            Button {
                                FinderActions.reveal(build.outputURL)
                            } label: { Label("Reveal", systemImage: "finder") }
                            .tint(.blue)
                        }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func contextMenu(for build: BuildRecord) -> some View {
        Button { FinderActions.reveal(build.outputURL) } label: { Label("Reveal in Finder", systemImage: "finder") }
        Button { FinderActions.copyPath(build.outputURL) } label: { Label("Copy Path", systemImage: "doc.on.doc") }
        Divider()
        Button(role: .destructive) {
            history.remove(build, deleteFile: false)
        } label: { Label("Remove from History", systemImage: "trash") }
        Button(role: .destructive) {
            history.remove(build, deleteFile: true)
        } label: { Label("Remove & Delete IPA", systemImage: "trash.slash") }
    }
}

private struct BuildRow: View {
    let build: BuildRecord

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: build.status.systemImage)
                .font(.title3)
                .foregroundStyle(Theme.statusColor(build.status))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(build.projectName).font(.callout.weight(.semibold))
                    Text("\(build.version) (\(build.buildNumber))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(build.outputURL.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(build.formattedSize).font(.caption.weight(.medium))
                Text(build.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            StatusBadge(status: build.status, compact: true)

            Button { FinderActions.reveal(build.outputURL) } label: {
                Image(systemName: "finder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")

            Button { FinderActions.copyPath(build.outputURL) } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy path")
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
