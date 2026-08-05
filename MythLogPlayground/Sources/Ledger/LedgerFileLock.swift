import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// A ledger file open with a POSIX advisory lock held for as long as this object
/// lives.
///
/// # Why a lock at all, when the reader is an actor
///
/// Actor isolation serialises *the threads of this process*. The lock exists for
/// a different process entirely: the shipping recorder, which appends under
/// `LOCK_EX`. Without a shared lock a reader can observe a half-written final
/// line, and a half-written line is indistinguishable from a truncated ledger —
/// so the viewer would raise a tamper alarm because it happened to read at an
/// unlucky microsecond. That is the worst possible false positive for a product
/// whose claim is an accurate record.
///
/// # Why the lock is held for the whole stream
///
/// It delays the recorder's next append for the duration of the read, which is
/// real and deliberate. The alternative — snapshot the bytes, release, then
/// parse — means holding the entire ledger in memory, which is the thing
/// streaming exists to avoid. One delayed append is the correct trade.
///
/// # Why acquisition is `async` and non-blocking
///
/// `flock(2)` without `LOCK_NB` blocks the calling thread. Swift's cooperative
/// pool has a small, fixed number of threads and blocking one can stall
/// unrelated work, including the UI's own tasks. So this takes the lock with
/// `LOCK_NB` and, on contention, *suspends* rather than blocks. Suspension is
/// also what makes it cancellable: a zoom that supersedes this read stops here
/// rather than after the timeout.
///
/// Not `Sendable`, deliberately: a file descriptor with a lock attached has
/// exactly one owner, and the compiler should enforce that.
final class LockedFile {
    enum Mode {
        /// Many readers, no writer. Used for everything the viewer does.
        case shared
        /// One writer, no readers. Used only by `append`.
        case exclusive

        #if canImport(Darwin)
            var flockOperation: Int32 {
                switch self {
                case .shared: LOCK_SH
                case .exclusive: LOCK_EX
                }
            }
        #endif
    }

    let url: URL
    let handle: FileHandle
    private var isLocked = false

    /// An append writes one short line under the exclusive lock, so contention
    /// lasting seconds means something is wrong rather than busy.
    static let acquisitionTimeout: Duration = .seconds(2)
    private static let retryDelay: Duration = .milliseconds(10)

    private init(url: URL, handle: FileHandle) {
        self.url = url
        self.handle = handle
    }

    /// Opens `url` for reading and takes a shared lock.
    static func openForReading(_ url: URL) async throws -> LockedFile {
        try await open(url, mode: .shared) { try FileHandle(forReadingFrom: $0) }
    }

    /// Opens `url` for reading and writing and takes an exclusive lock.
    static func openForUpdating(_ url: URL) async throws -> LockedFile {
        try await open(url, mode: .exclusive) { try FileHandle(forUpdating: $0) }
    }

    private static func open(
        _ url: URL,
        mode: Mode,
        makeHandle: (URL) throws -> FileHandle
    ) async throws -> LockedFile {
        let handle: FileHandle
        do {
            handle = try makeHandle(url)
        } catch {
            throw LedgerError.unreadableSegment(path: url.path, underlying: String(describing: error))
        }

        let file = LockedFile(url: url, handle: handle)
        try await file.lock(mode)
        return file
    }

    private func lock(_ mode: Mode) async throws {
        #if canImport(Darwin)
            let deadline = ContinuousClock.now + Self.acquisitionTimeout
            while true {
                if flock(handle.fileDescriptor, mode.flockOperation | LOCK_NB) == 0 {
                    isLocked = true
                    return
                }

                let code = errno
                guard code == EWOULDBLOCK || code == EINTR else {
                    try? handle.close()
                    throw LedgerError.unreadableSegment(
                        path: url.path,
                        underlying: "flock failed with errno \(code)"
                    )
                }

                guard ContinuousClock.now < deadline else {
                    try? handle.close()
                    throw LedgerError.lockUnavailable(
                        path: url.path,
                        afterSeconds: Double(Self.acquisitionTimeout.components.seconds)
                    )
                }

                // Cancellable: `Task.sleep` throws `CancellationError`, so a
                // superseded read abandons the attempt instead of waiting out
                // the timeout.
                do {
                    try await Task.sleep(for: Self.retryDelay)
                } catch {
                    try? handle.close()
                    throw error
                }
            }
        #else
            _ = mode
            isLocked = false
        #endif
    }

    /// Releases the lock and closes the descriptor. Idempotent, and also run
    /// from `deinit`, so abandoning an iteration part-way — which is exactly
    /// what cancellation does — cannot leak a held lock.
    func close() {
        #if canImport(Darwin)
            if isLocked {
                flock(handle.fileDescriptor, LOCK_UN)
                isLocked = false
            }
        #endif
        try? handle.close()
    }

    deinit {
        close()
    }
}
