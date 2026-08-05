import CryptoKit
import Foundation

/// The only thing in the app that touches a ledger file.
///
/// # Why an `actor`
///
/// Several readers — the timeline load, a background verification, an export —
/// can want the ledger at once. Actor isolation serialises them without a single
/// lock, queue, or completion handler appearing in this file.
///
/// The shipping app achieves the same thing inside an actor by hand: an
/// `ioTail: Task<Void, Never>` chain that each operation appends itself to, run
/// on detached tasks. That re-implements the isolation the `actor` keyword
/// already provides, and does it with detached tasks that escape the actor's
/// priority and cancellation. None of it is carried across.
///
/// # What is still not the actor's job
///
/// - `flock(2)` remains, because the recorder is a *different process* and actor
///   isolation says nothing about it.
/// - Streaming happens outside the actor. ``entries()`` returns a value
///   describing what to read; iterating it does not occupy the actor, so a
///   ten-minute read of a two-year ledger does not block a verification.
/// - Hashing is synchronous. It is pure computation on values in memory and
///   making it `async` would add a suspension point that means nothing.
actor LedgerStore {
    /// The active, still-being-appended segment. Rotated segments are discovered
    /// relative to it.
    let activeURL: URL

    private let hmacKey: Data
    private let maxFileBytes: Int?
    private let fileManager: FileManager

    /// A value, not an object, so mutating it is actor-isolated by construction.
    /// See ``SegmentRecordCounting`` for why the object version does not survive
    /// strict concurrency.
    private var countCache = SegmentCountCache()

    /// - Parameter fileManager: taken as `sending`, so the actor becomes its
    ///   sole owner.
    ///
    ///   `FileManager` is explicitly non-`Sendable` (`@_nonSendable(_assumed)`
    ///   in Foundation), which is the whole difficulty: the shipping app wraps
    ///   it in `private struct LedgerFileManager: @unchecked Sendable` so it can
    ///   be captured by detached tasks. That conformance asserts a thread-safety
    ///   property nothing establishes — `FileManager.default` is shared
    ///   process-wide and has mutable delegate state.
    ///
    ///   `sending` says the honest thing instead: the caller hands over a value
    ///   it will not touch again, and the compiler *proves* the caller cannot.
    ///   The default argument constructs a fresh instance, which is trivially in
    ///   its own region. Passing `FileManager.default` here is a compile error,
    ///   which is the correct outcome.
    init(
        ledgerURL: URL,
        hmacKey: Data,
        maxFileBytes: Int? = nil,
        fileManager: sending FileManager = FileManager()
    ) throws {
        guard !hmacKey.isEmpty else { throw LedgerError.emptyHMACKey }

        self.activeURL = ledgerURL
        self.hmacKey = hmacKey
        self.maxFileBytes = (maxFileBytes ?? 0) > 0 ? maxFileBytes : nil
        self.fileManager = fileManager
    }

    /// The number of records in one segment, from cache when the cache still
    /// describes the file on disk.
    ///
    /// `cacheable` is false for the active segment, which is still growing.
    private func recordCount(of url: URL, cacheable: Bool) async throws -> Int {
        let fingerprint = try SegmentRecordCounting.fingerprint(of: url, fileManager: fileManager)

        if cacheable, let cached = countCache.count(for: url, matching: fingerprint) {
            return cached
        }

        // `static`, and its arguments are `Sendable`, so suspending here carries
        // nothing out of the actor.
        let count = try await SegmentRecordCounting.countRecords(in: url)

        if cacheable {
            countCache.remember(count: count, for: url, fingerprint: fingerprint)
        }
        return count
    }

    // MARK: - Chain layout

    /// Every segment in chain order, each carrying the cumulative ordinal of the
    /// records before it.
    ///
    /// Counting a rotated segment happens at most once ever (see
    /// ``SegmentRecordCounting``), so this is cheap on every load but the first.
    func chain() async throws -> LedgerChain {
        var urls = try LedgerSegmentNaming.rotatedSegmentURLs(for: activeURL, fileManager: fileManager)

        // A ledger that has never been written has no active file yet. That is
        // an empty ledger, not an unreadable one.
        let hasActive = fileManager.fileExists(atPath: activeURL.path)
        if hasActive { urls.append(activeURL) }

        var segments = [LedgerSegment]()
        var base = 0
        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()
            let isActive = hasActive && index == urls.count - 1
            segments.append(LedgerSegment(index: index, url: url, isActive: isActive, baseOrdinal: base))

            // The last segment's own count is never needed to place a later
            // segment, so it is not paid for here.
            if index < urls.count - 1 {
                base += try await recordCount(of: url, cacheable: true)
            }
        }

        return LedgerChain(segments: segments)
    }

    /// Every record in the ledger, in order, streamed.
    ///
    /// Returns a description of what to read rather than the records themselves.
    /// Iterating it opens one segment at a time; nothing proportional to the
    /// size of the history is ever held in memory, here or by the caller.
    func entries() async throws -> LedgerRecordSequence {
        LedgerRecordSequence(segments: try await chain().segments)
    }

    /// The number of records in the whole chain.
    func recordCount() async throws -> Int {
        let chain = try await chain()
        guard let last = chain.segments.last else { return 0 }
        return last.baseOrdinal + (try await recordCount(of: last.url, cacheable: !last.isActive))
    }

    /// The hash at the head of the chain — what the next appended record must
    /// point back to, and what an anchor records.
    ///
    /// Reads backwards from the end of the last non-empty segment rather than
    /// streaming forwards, because on a ledger with no rotation configured the
    /// active file *is* the whole history and reading it to find its last line
    /// would make every append O(history).
    func lastHash() async throws -> String {
        let chain = try await chain()
        for segment in chain.segments.reversed() {
            if let line = try await Self.lastNonEmptyLine(of: segment.url) {
                let record = try CanonicalJSON.decode(LedgerRecord.self, from: line)
                return record.hash
            }
        }
        return LedgerHashChain.zeroHash
    }

    // MARK: - Verification

    /// Verifies the whole chain: every record's HMAC, every record-to-record
    /// link, and every seam between rotated segments.
    ///
    /// # Why a `TaskGroup`
    ///
    /// A segment's internal chain is self-contained — record *n* links to record
    /// *n−1* within the same file — so segments can be verified independently
    /// and only the seams between them need ordering. Verification is
    /// HMAC-bound, so on a multi-core Mac this is close to a linear speed-up in
    /// the number of segments, and a two-year ledger is many segments.
    ///
    /// The children call a `nonisolated static` function on purpose. An
    /// actor-isolated method would make every child queue on this actor and the
    /// fan-out would be theatre.
    ///
    /// Results arrive in any order, so each child stamps its own segment index
    /// and the parent sorts before checking seams.
    ///
    /// # Why failures are results, not errors
    ///
    /// A record that will not decode is reported as a ``LedgerIssue``, not
    /// thrown. Throwing would leave the caller with no verification at all, and
    /// the UI would have to render "we could not check" — which reads as empty.
    /// A ledger that fails verification must be reported as failing.
    func verify() async throws -> LedgerVerification {
        let chain = try await chain()
        guard !chain.segments.isEmpty else { return .empty() }

        let hmacKey = self.hmacKey
        let verifications = try await withThrowingTaskGroup(of: SegmentVerification.self) { group in
            for segment in chain.segments {
                group.addTask {
                    try await LedgerStore.verifySegment(segment, hmacKey: hmacKey)
                }
            }

            var collected = [SegmentVerification]()
            collected.reserveCapacity(chain.segments.count)
            for try await verification in group {
                collected.append(verification)
            }
            return collected.sorted { $0.index < $1.index }
        }

        return Self.stitch(verifications, segments: chain.segments)
    }

    /// Verifies one segment's internal chain. `nonisolated static` so children
    /// of the task group genuinely run in parallel rather than re-entering the
    /// actor one at a time.
    private nonisolated static func verifySegment(
        _ segment: LedgerSegment,
        hmacKey: Data
    ) async throws -> SegmentVerification {
        let key = try LedgerHashChain.symmetricKey(from: hmacKey)

        var issues = [LedgerIssue]()
        var count = 0
        var firstPreviousHash: String?
        var lastHash: String?
        var expectedPreviousHash: String?

        do {
            for try await entry in LedgerRecordSequence(segments: [segment]) {
                try Task.checkCancellation()

                if firstPreviousHash == nil {
                    firstPreviousHash = entry.record.previousHash
                }

                issues.append(
                    contentsOf: try LedgerHashChain.issues(
                        for: entry.record,
                        ordinal: entry.ordinal,
                        expectedPreviousHash: expectedPreviousHash,
                        key: key
                    ))

                expectedPreviousHash = entry.record.hash
                lastHash = entry.record.hash
                count += 1
            }
        } catch let error as LedgerError {
            guard case .malformedRecord(let ordinal, _, let underlying) = error else { throw error }
            // Truncation and corruption land here. They are integrity findings
            // about a real ledger, not failures to read one.
            issues.append(LedgerIssue(kind: .undecodableRecord, ordinal: ordinal, detail: underlying))
        }

        return SegmentVerification(
            index: segment.index,
            recordCount: count,
            firstPreviousHash: firstPreviousHash,
            lastHash: lastHash,
            issues: issues
        )
    }

    /// Joins independently-verified segments and checks the seams between them.
    ///
    /// The first segment must start from the zero hash; every later segment must
    /// start from the hash the previous one ended on. Empty segments are skipped
    /// rather than treated as a break — a segment can legitimately be empty
    /// immediately after rotation.
    private nonisolated static func stitch(
        _ verifications: [SegmentVerification],
        segments: [LedgerSegment]
    ) -> LedgerVerification {
        var issues = verifications.flatMap(\.issues)
        var expectedPreviousHash = LedgerHashChain.zeroHash
        var recordCount = 0
        var lastHash = LedgerHashChain.zeroHash

        for verification in verifications {
            if let firstPreviousHash = verification.firstPreviousHash,
                firstPreviousHash != expectedPreviousHash
            {
                let base = segments.first { $0.index == verification.index }?.baseOrdinal ?? recordCount
                issues.append(
                    LedgerIssue(
                        kind: .segmentSeamMismatch,
                        ordinal: base + 1,
                        detail: "expected \(expectedPreviousHash), found \(firstPreviousHash)"
                    ))
            }

            if let segmentLastHash = verification.lastHash {
                expectedPreviousHash = segmentLastHash
                lastHash = segmentLastHash
            }
            recordCount += verification.recordCount
        }

        return LedgerVerification(
            isValid: issues.isEmpty,
            recordCount: recordCount,
            segmentCount: verifications.count,
            lastHash: lastHash,
            issues: issues.sorted { $0.ordinal < $1.ordinal }
        )
    }

    // MARK: - Appending

    /// Appends one event, rotating first if the active segment has reached its
    /// size limit.
    ///
    /// The playground does not record; this exists because the ledger format is
    /// only meaningfully tested by writing one, and because a proof export has
    /// to be able to reproduce a chain the recorder would accept.
    /// # Everything under the lock uses the handle it already holds
    ///
    /// `flock(2)` is per open file description, not per process. Opening the
    /// active segment a second time — to count it, or to read its head — while
    /// this call holds the exclusive lock deadlocks against itself, and the only
    /// symptom is a two-second stall followed by ``LedgerError/lockUnavailable``.
    /// So the layout is resolved *before* the lock is taken, and every read
    /// inside the critical section goes through `file.handle`.
    @discardableResult
    func append(_ event: AlarmEvent) async throws -> LedgerEntry {
        try await rotateIfNeeded()
        try ensureActiveFileExists()

        // Resolved before locking: this touches the rotated segments, never the
        // active one.
        let chain = try await chain()
        let active = chain.segments.last
        let fallbackPreviousHash = try await lastRotatedHash()

        let file = try await LockedFile.openForUpdating(activeURL)
        defer { file.close() }

        // Counted and read *under the exclusive lock*: between deciding the
        // predecessor and writing, no other process may append, or two records
        // would claim the same one.
        let existingRecords = try Self.countRecords(in: file.handle)
        let previousHash =
            try Self.lastNonEmptyLine(of: file.handle)
            .map { try CanonicalJSON.decode(LedgerRecord.self, from: $0).hash }
            ?? fallbackPreviousHash

        let key = try LedgerHashChain.symmetricKey(from: hmacKey)
        let hash = try LedgerHashChain.hash(event: event, previousHash: previousHash, key: key)
        let record = LedgerRecord(event: event, previousHash: previousHash, hash: hash)

        try file.handle.seekToEnd()
        try file.handle.write(contentsOf: try CanonicalJSON.encodeLine(record))

        return LedgerEntry(
            ordinal: (active?.baseOrdinal ?? 0) + existingRecords + 1,
            segmentIndex: active?.index ?? 0,
            record: record
        )
    }

    /// The chain head as of the last rotated segment — the predecessor for the
    /// first record written into a freshly rotated, still-empty active file.
    private func lastRotatedHash() async throws -> String {
        let rotated = try LedgerSegmentNaming.rotatedSegmentURLs(for: activeURL, fileManager: fileManager)
        for url in rotated.reversed() {
            if let line = try await Self.lastNonEmptyLine(of: url) {
                return try CanonicalJSON.decode(LedgerRecord.self, from: line).hash
            }
        }
        return LedgerHashChain.zeroHash
    }

    private func ensureActiveFileExists() throws {
        try fileManager.createDirectory(
            at: activeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: activeURL.path) {
            fileManager.createFile(atPath: activeURL.path, contents: nil)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: activeURL.path)
        }
    }

    /// Archives the active segment and seeds a new one with a `ledger.rotated`
    /// record, so continuity across the seam is itself a verifiable record
    /// rather than an inference.
    private func rotateIfNeeded() async throws {
        guard let maxFileBytes,
            fileManager.fileExists(atPath: activeURL.path),
            let size = try? fileManager.attributesOfItem(atPath: activeURL.path)[.size] as? NSNumber,
            size.intValue >= maxFileBytes
        else {
            return
        }

        let previousHash = try await lastHash()
        guard previousHash != LedgerHashChain.zeroHash else { return }

        let archiveURL = try availableRotatedSegmentURL()
        try fileManager.moveItem(at: activeURL, to: archiveURL)
        try ensureActiveFileExists()

        let key = try LedgerHashChain.symmetricKey(from: hmacKey)
        let event = AlarmEvent(
            source: "ledger",
            name: "ledger.rotated",
            metadata: ["archivedSegment": archiveURL.lastPathComponent]
        )
        let hash = try LedgerHashChain.hash(event: event, previousHash: previousHash, key: key)
        let record = LedgerRecord(event: event, previousHash: previousHash, hash: hash)

        let file = try await LockedFile.openForUpdating(activeURL)
        defer { file.close() }
        try file.handle.seekToEnd()
        try file.handle.write(contentsOf: try CanonicalJSON.encodeLine(record))
    }

    /// Matches the shipping recorder's naming exactly, including the UTC stamp
    /// format, so segments written by either process sort into one chain.
    private func availableRotatedSegmentURL() throws -> URL {
        let parent = activeURL.deletingLastPathComponent()
        let ext = activeURL.pathExtension
        let stamp = Date.now.formatted(
            .verbatim(
                """
                \(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)\
                T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\
                \(minute: .twoDigits)\(second: .twoDigits)\(secondFraction: .fractional(3))
                """,
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: TimeZone(identifier: "UTC") ?? .gmt,
                calendar: Calendar(identifier: .gregorian)
            ))

        var counter = 0
        while true {
            let name = LedgerSegmentNaming.rotatedPrefix(for: activeURL) + stamp + String(format: "-%03d", counter)
            var candidate = parent.appendingPathComponent(name)
            if !ext.isEmpty { candidate = candidate.appendingPathExtension(ext) }
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    // MARK: - Tail reading

    /// The last non-empty line of a file, read backwards from the end.
    ///
    /// Reading forwards would be O(file) and this is on the append path.
    private nonisolated static func lastNonEmptyLine(of url: URL) async throws -> Data? {
        let file = try await LockedFile.openForReading(url)
        defer { file.close() }
        return try lastNonEmptyLine(of: file.handle)
    }

    /// Counts non-empty lines through an already-open, already-locked handle.
    /// The unlocked equivalent is ``SegmentRecordCounting/countRecords(in:)``;
    /// this variant exists so `append` never opens the file twice.
    private nonisolated static func countRecords(in handle: FileHandle) throws -> Int {
        try handle.seek(toOffset: 0)
        var count = 0
        var sawBytesSinceNewline = false

        while let chunk = try handle.read(upToCount: SegmentRecordCounting.chunkBytes), !chunk.isEmpty {
            for byte in chunk {
                if byte == 0x0A {
                    if sawBytesSinceNewline { count += 1 }
                    sawBytesSinceNewline = false
                } else {
                    sawBytesSinceNewline = true
                }
            }
        }

        if sawBytesSinceNewline { count += 1 }
        return count
    }

    private nonisolated static func lastNonEmptyLine(of handle: FileHandle) throws -> Data? {
        let chunkBytes = 64 << 10
        var end = Int(try handle.seekToEnd())
        guard end > 0 else { return nil }

        var tail = Data()
        while end > 0 {
            let start = max(0, end - chunkBytes)
            try handle.seek(toOffset: UInt64(start))
            let chunk = try handle.read(upToCount: end - start) ?? Data()
            tail = chunk + tail
            end = start

            // Trailing newlines are separators, not content; strip them before
            // looking for the boundary of the last real line.
            var scan = tail
            while scan.last == 0x0A { scan.removeLast() }
            if scan.isEmpty {
                if end == 0 { return nil }
                continue
            }
            if let boundary = scan.lastIndex(of: 0x0A) {
                return scan[scan.index(after: boundary)...]
            }
            if end == 0 { return scan }
        }
        return nil
    }
}
