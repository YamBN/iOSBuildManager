import Darwin
import Foundation

/// Local, versioned command contract used by the CLI and the scheduler.
struct BuildRequest: Codable, Equatable {
    var version: Int = 1
    var id: UUID = UUID()
    var action: String = "enqueue"
    var projectId: UUID?
    var projectPath: String?
    var scheme: String?
    var configuration: String?
    var outputDirectory: String?
    var targetId: UUID?
    var clean: Bool? = nil
    var installOnDevice: Bool? = nil
}

struct QueuedBuild: Codable, Identifiable {
    var id: UUID { request.id }
    var request: BuildRequest
    var project: Project?
    var settings: AppSettings?
    var state: String = "queued"
    var createdAt: Date = .now
    var startedAt: Date?
    var finishedAt: Date?
    var artifactPath: String?
    var error: String?
    var installResult: String?
}

struct BuildQueueState: Codable {
    var version = 1
    var paused = false
    var jobs: [QueuedBuild] = []
}

/// One durable queue shared by GUI, CLI and scheduled requests. Only the process
/// holding worker.lock may read commands or start work. Persist BEFORE running.
/// A crash leaves running work interrupted and pauses dispatch for inspection.
@MainActor
final class BuildQueue: ObservableObject {
    @Published private(set) var state = BuildQueueState()
    @Published private(set) var lastError: String?
    var resolve: ((BuildRequest) throws -> (Project, AppSettings))?
    var run: ((QueuedBuild) -> Void)?
    private let directory: URL
    private var lockFD: Int32 = -1
    private var timer: Task<Void, Never>?
    private var activeId: UUID?
    private var healthy = true
    var ownsWorker: Bool { lockFD >= 0 }
    var pendingCount: Int { state.jobs.filter { $0.state == "queued" }.count }
    var inbox: URL { directory.appendingPathComponent("inbox", isDirectory: true) }
    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    init(directory: URL) { self.directory = directory }

    deinit {
        timer?.cancel()
        if lockFD >= 0 { close(lockFD) }
    }

    func start(poll: Bool = true) {
        guard !ownsWorker else { return }
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            let fd = open(directory.appendingPathComponent("worker.lock").path,
                          O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw failure("Cannot open queue lock.") }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                close(fd)
                lastError = "Another iOS Build Manager instance owns the queue."
                return
            }
            lockFD = fd
            if FileManager.default.fileExists(atPath: stateURL.path) {
                state = try JSONDecoder().decode(BuildQueueState.self, from: Data(contentsOf: stateURL))
                guard state.version == 1 else { throw failure("Unsupported queue version.") }
            }
            var recovered = state
            for i in recovered.jobs.indices where recovered.jobs[i].state == "running" {
                recovered.jobs[i].state = "interrupted"
                recovered.jobs[i].finishedAt = .now
                recovered.jobs[i].error = "Worker stopped before reporting completion. Check for orphan build processes before resuming."
                recovered.paused = true
            }
            try commit(recovered)
            if poll {
                timer = Task { [weak self] in
                    while !Task.isCancelled {
                        self?.tick()
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
            }
        } catch { stopOnError(error) }
    }

    /// Also used by GUI actions: publish an atomic command for the single owner.
    func submit(_ request: BuildRequest) throws {
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(request)
        let url = inbox.appendingPathComponent(request.id.uuidString + ".json")
        let temporary = inbox.appendingPathComponent(".request-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        try FileManager.default.linkItem(at: temporary, to: url)
    }

    func tick() {
        guard ownsWorker, healthy else { return }
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: inbox,
                includingPropertiesForKeys: [.creationDateKey]).filter { $0.pathExtension == "json" }
                .sorted {
                    let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return a == b ? $0.lastPathComponent < $1.lastPathComponent : a < b
                }
            for url in urls {
                // Bad requests get a durable rejection; they never block later commands.
                let request: BuildRequest
                do {
                    let data = try Data(contentsOf: url)
                    guard data.count <= 65_536 else { throw failure("Request exceeds 64 KiB.") }
                    request = try JSONDecoder().decode(BuildRequest.self, from: data)
                    guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) == request.id else {
                        throw failure("Request ID must match its filename.")
                    }
                } catch {
                    let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
                    if !state.jobs.contains(where: { $0.id == id }) {
                        var next = state
                        next.jobs.append(QueuedBuild(request: BuildRequest(id: id), state: "rejected",
                                                     finishedAt: .now, error: "Malformed request."))
                        try commit(next)
                    }
                    try FileManager.default.removeItem(at: url)
                    continue
                }
                if !state.jobs.contains(where: { $0.id == request.id }) {
                    try accept(request)
                }
                // Receipt is already durable, so a crash here cannot duplicate execution.
                try FileManager.default.removeItem(at: url)
            }
            guard activeId == nil, !state.paused, let run,
                  let index = state.jobs.firstIndex(where: { $0.state == "queued" }) else { return }
            var next = state
            next.jobs[index].state = "running"
            next.jobs[index].startedAt = .now
            try commit(next)
            activeId = state.jobs[index].id
            run(state.jobs[index])
        } catch { stopOnError(error) }
    }

    private func accept(_ request: BuildRequest) throws {
        var next = state
        var job = QueuedBuild(request: request)
        do {
            guard request.version == 1 else { throw failure("Unsupported request version.") }
            switch request.action {
            case "enqueue":
                guard let resolve else { throw failure("Build resolver unavailable.") }
                let (project, settings) = try resolve(request)
                job.project = project
                job.settings = settings
            case "cancel":
                guard let i = next.jobs.firstIndex(where: { $0.id == request.targetId }),
                      next.jobs[i].state == "queued" else {
                    throw failure("Only queued jobs can be cancelled. Use the app to stop an active build.")
                }
                next.jobs[i].state = "cancelled"
                next.jobs[i].finishedAt = .now
                job.state = "completed"
                job.finishedAt = .now
            case "resume":
                next.paused = false
                job.state = "completed"
                job.finishedAt = .now
            default: throw failure("Unknown action.")
            }
        } catch {
            job.state = "rejected"
            job.error = error.localizedDescription
            job.finishedAt = .now
        }
        next.jobs.append(job)
        try commit(next)
    }

    func complete(state result: String, artifactPath: String? = nil, error: String? = nil,
                  installResult: String? = nil) {
        guard let id = activeId, let i = state.jobs.firstIndex(where: { $0.id == id }) else { return }
        do {
            var next = state
            next.jobs[i].state = result
            next.jobs[i].finishedAt = .now
            next.jobs[i].artifactPath = artifactPath
            next.jobs[i].error = error
            next.jobs[i].installResult = installResult
            try commit(next)
            activeId = nil
        } catch { stopOnError(error) }
    }

    private func commit(_ next: BuildQueueState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: stateURL, options: .atomic)
        state = next
    }

    private func stopOnError(_ error: Error) {
        healthy = false
        lastError = "Queue stopped: \(error.localizedDescription)"
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "BuildQueue", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
