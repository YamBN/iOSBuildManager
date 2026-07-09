import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var engine: BuildEngine
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if engine.isBuilding {
                progressRow
            }
            Divider()
            logScroll
            Divider()
            toolbar
        }
        .navigationTitle("Logs")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: engine.status.systemImage)
                .font(.title2)
                .foregroundStyle(Theme.statusColor(engine.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.currentProjectName ?? "No active build")
                    .font(.headline)
                if let started = engine.buildStartedAt {
                    Text("Started \(started.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            StatusBadge(status: engine.status)
        }
        .padding(16)
    }

    private var progressRow: some View {
        HStack(spacing: 12) {
            if let progress = engine.estimatedProgress {
                ProgressView(value: progress, total: 1)
                Text("\(Int(progress * 100))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(BuildProgressEstimator.formattedElapsed(engine.elapsedSeconds))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var logScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(engine.logLines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(.callout, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(idx)
                    }
                }
                .padding(12)
            }
            .background(.black.opacity(0.05))
            .onChange(of: engine.logLines.count) { _ in
                withAnimation {
                    proxy.scrollTo(engine.logLines.count - 1, anchor: .bottom)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if engine.isBuilding {
                Button(role: .destructive) { engine.cancel() } label: {
                    Label("Cancel Build", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    if let p = model.selectedProject ?? model.projects.projects.first {
                        model.startBuild(for: p.id)
                    } else {
                        model.selection = .settings
                    }
                } label: {
                    Label("Start Build", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Button { engine.reset() } label: {
                Label("Clear", systemImage: "eraser")
            }
            .buttonStyle(.bordered)
            .disabled(engine.isBuilding || engine.logLines.isEmpty)

            Spacer()

            if let err = engine.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text("\(engine.logLines.count) lines")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}
