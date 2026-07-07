import Foundation

/// Persisted build history with automatic pruning to the configured size.
@MainActor
final class BuildHistoryStore: ObservableObject {
    @Published private(set) var builds: [BuildRecord] = []

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: AppPaths.historyURL),
              let decoded = try? JSONDecoder().decode([BuildRecord].self, from: data)
        else { return }
        builds = decoded.sorted(by: { $0.date > $1.date })
    }

    func save() {
        let sorted = builds.sorted(by: { $0.date > $1.date })
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        try? data.write(to: AppPaths.historyURL, options: .atomic)
    }

    func add(_ record: BuildRecord) {
        builds.insert(record, at: 0)
        save()
    }

    func remove(_ record: BuildRecord, deleteFile: Bool = false) {
        if deleteFile {
            try? FileManager.default.removeItem(at: record.outputURL)
        }
        builds.removeAll { $0.id == record.id }
        save()
    }

    func clear() {
        builds.removeAll()
        save()
    }

    /// Keeps only the most recent `count` records (history UI retention).
    func prune(to count: Int) {
        guard builds.count > count else { return }
        builds = Array(builds.sorted(by: { $0.date > $1.date }).prefix(count))
        save()
    }

    var mostRecent: BuildRecord? {
        builds.sorted(by: { $0.date > $1.date }).first
    }

    var mostRecentSuccess: BuildRecord? {
        builds.sorted(by: { $0.date > $1.date }).first { $0.status == .success }
    }
}
