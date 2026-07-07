import Foundation

/// Persisted list of saved projects.
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: AppPaths.projectsURL),
              let decoded = try? JSONDecoder().decode([Project].self, from: data)
        else { return }
        projects = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: AppPaths.projectsURL, options: .atomic)
    }

    func upsert(_ project: Project) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        } else {
            projects.append(project)
        }
        save()
    }

    func remove(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        save()
    }

    func project(with id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    /// Updates a project in place with the given mutation, persisting the result.
    func update(_ id: UUID, _ mutate: (inout Project) -> Void) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        mutate(&projects[idx])
        save()
    }

    func markBuilt(projectId: UUID) {
        update(projectId) { $0.lastBuiltAt = .now }
    }
}
