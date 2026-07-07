import Foundation

/// Sendable box holding a process exit code, written from a background
/// termination handler and read on the main actor once the log stream ends.
final class ExitCodeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int32 = -1

    func set(_ code: Int32) {
        lock.lock(); defer { lock.unlock() }
        stored = code
    }

    var value: Int32 {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}

/// An eager, buffered bridge between a background `Pipe` readability handler
/// and a main-actor `AsyncStream` consumer.
///
/// Lines yielded before the consumer starts iterating are buffered and flushed
/// the moment iteration begins, so no early log output is lost. This avoids
/// `AsyncStream.makeStream` (macOS 14+) so the app runs on macOS 13.
final class EagerLineChannel: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [String] = []
    private var continuation: AsyncStream<String>.Continuation?
    private(set) var stream: AsyncStream<String>!

    init() {
        let s = AsyncStream<String> { [weak self] cont in
            guard let self else { return }
            self.lock.lock()
            self.continuation = cont
            let pending = self.buffer
            self.buffer.removeAll()
            self.lock.unlock()
            for line in pending { cont.yield(line) }
            cont.onTermination = { [weak self] _ in self?.finish() }
        }
        self.stream = s
    }

    func yield(_ line: String) {
        lock.lock()
        let cont = continuation
        if cont == nil { buffer.append(line) }
        lock.unlock()
        cont?.yield(line)
    }

    func finish() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.finish()
    }
}
