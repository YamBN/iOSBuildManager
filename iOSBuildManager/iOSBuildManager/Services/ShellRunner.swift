import Foundation

/// Thread-safe accumulator that splits an incoming byte stream into UTF-8 lines.
final class LineBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        var lines: [String] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<nl])
            buffer = Data(buffer[buffer.index(after: nl)...])
            if let s = String(data: line, encoding: .utf8) {
                lines.append(s)
            }
        }
        return lines
    }

    func flush() -> String? {
        lock.lock(); defer { lock.unlock() }
        if buffer.isEmpty { return nil }
        let s = String(data: buffer, encoding: .utf8)
        buffer.removeAll()
        return s
    }
}

/// Helpers for running command-line tools via `Process`.
enum ShellRunner {
    /// Runs a command and returns all stdout/stderr lines. Does not throw on a
    /// non-zero exit code (callers inspect output themselves); only throws when
    /// the process cannot be launched.
    static func collect(command: String, arguments: [String], cwd: URL? = nil) async throws -> [String] {
        var lines: [String] = []
        for try await line in stream(command: command, arguments: arguments, cwd: cwd, throwOnNonZero: false) {
            lines.append(line)
        }
        return lines
    }

    /// Runs a command and yields stdout/stderr lines as they arrive.
    static func stream(
        command: String,
        arguments: [String],
        cwd: URL? = nil,
        throwOnNonZero: Bool = true
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments
                if let cwd { process.currentDirectoryURL = cwd }

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                let handle = pipe.fileHandleForReading
                let lineBuffer = LineBuffer()
                handle.readabilityHandler = { h in
                    let data = h.availableData
                    guard !data.isEmpty else { return }
                    for line in lineBuffer.append(data) {
                        continuation.yield(line)
                    }
                }

                do {
                    try process.run()
                } catch {
                    handle.readabilityHandler = nil
                    continuation.finish(throwing: error)
                    return
                }

                process.waitUntilExit()
                handle.readabilityHandler = nil

                let trailing = handle.availableData
                if !trailing.isEmpty {
                    for line in lineBuffer.append(trailing) {
                        continuation.yield(line)
                    }
                }
                if let remaining = lineBuffer.flush() {
                    continuation.yield(remaining)
                }

                let status = process.terminationStatus
                if status != 0 && throwOnNonZero {
                    continuation.finish(throwing: BuildError.processFailed(command: (process.executableURL?.lastPathComponent ?? command), exitCode: status))
                } else {
                    continuation.finish()
                }
            }
        }
    }
}
