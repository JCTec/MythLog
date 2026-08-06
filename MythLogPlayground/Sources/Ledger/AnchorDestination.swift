import Foundation

/// Somewhere an anchor can be kept.
///
/// # Why this is a protocol now
///
/// An anchor is three fields — a record count, the chain head, and a timestamp —
/// and **no event content**. That is what makes the question tractable: putting
/// an anchor somewhere does not put anyone's history there. So the list of
/// plausible places is long (a folder, a USB key, a git remote, a chat, a
/// timestamping service), and every one of them is the same three operations.
///
/// Behind one interface, each new destination is purely additive: nothing that
/// exists has to change for a new one to work. Before this, "add a destination"
/// meant editing a `switch` in the writer, and every such edit is a chance to
/// break the two that already worked.
///
/// # What a destination is judged on
///
/// From `docs/ANCHOR_DESTINATIONS.md`, in order:
///
/// 1. **Outside the adversary's control.** The one that actually matters.
/// 2. **Timestamped by a third party.** Independent corroboration of *when*.
/// 3. **Deletion is visible.** Append-only, or a hole you would notice.
/// 4. **No new infrastructure.** Something the person already has.
///
/// A conformer is not required to be good at any of these. It is required to be
/// honest about which ones it is bad at — see ``describedLocation``, and the
/// user-facing framing in `AnchorChoice`.
protocol AnchorDestination: Sendable {
    /// Where anchors go, in a form a person can check. Never throws: a
    /// destination that cannot currently be resolved must still be able to say
    /// what it was trying to resolve, or the failure is unattributable.
    var describedLocation: String { get }

    /// Records an anchor. Throws rather than falling back — writing an anchor
    /// somewhere other than where the user chose is worse than not writing one,
    /// because it looks like it worked.
    func write(_ anchor: LedgerHashAnchor) async throws

    /// The most recent anchor, or `nil` if none has been written.
    func latest() async throws -> LedgerHashAnchor?

    /// Every anchor ever written here, oldest first.
    ///
    /// The append-only history is what makes a rolled-back "latest" detectable:
    /// an adversary who overwrites the newest anchor still has to explain a
    /// history that ends somewhere else.
    func history() async throws -> [LedgerHashAnchor]
}

/// Anchors kept in a directory.
///
/// The one destination that has always existed. A plain folder covers both
/// shipped options — iCloud Drive is a folder that syncs, and "a folder you
/// choose" is a folder that might be on a USB key — which is why the *choice*
/// is about trust rather than about mechanism.
///
/// `anchor-latest.json` is the fast comparison surface. `anchor-history.jsonl`
/// is append-only, so a rolled-back "latest" is itself visible.
///
/// An `actor` because two writes must not interleave in the history file. The
/// exclusive `flock` in ``LockedFile`` already serialises *other processes*;
/// this serialises this one.
actor DirectoryAnchorDestination: AnchorDestination {
    static let latestFileName = "anchor-latest.json"
    static let historyFileName = "anchor-history.jsonl"

    let directory: URL
    private let fileManager: FileManager

    nonisolated var describedLocation: String { directory.path }

    /// `sending` for the same reason as ``LedgerStore``: `FileManager` is not
    /// `Sendable`, and this actor takes sole ownership rather than asserting
    /// that a shared one is safe.
    init(directory: URL, fileManager: sending FileManager = FileManager()) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func write(_ anchor: LedgerHashAnchor) async throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let line = try CanonicalJSON.encodeLine(anchor)

        let latestURL = directory.appendingPathComponent(Self.latestFileName)
        try line.write(to: latestURL, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: latestURL.path)

        let historyURL = directory.appendingPathComponent(Self.historyFileName)
        if !fileManager.fileExists(atPath: historyURL.path) {
            fileManager.createFile(atPath: historyURL.path, contents: nil)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
        }

        let file = try await LockedFile.openForUpdating(historyURL)
        defer { file.close() }
        try file.handle.seekToEnd()
        try file.handle.write(contentsOf: line)
    }

    func latest() throws -> LedgerHashAnchor? {
        let latestURL = directory.appendingPathComponent(Self.latestFileName)
        guard fileManager.fileExists(atPath: latestURL.path) else { return nil }
        return try CanonicalJSON.decode(LedgerHashAnchor.self, from: Data(contentsOf: latestURL))
    }

    func history() async throws -> [LedgerHashAnchor] {
        let historyURL = directory.appendingPathComponent(Self.historyFileName)
        guard fileManager.fileExists(atPath: historyURL.path) else { return [] }

        let file = try await LockedFile.openForReading(historyURL)
        defer { file.close() }

        var anchors = [LedgerHashAnchor]()
        for try await line in file.handle.bytes.lines {
            try Task.checkCancellation()
            guard !line.isEmpty else { continue }
            anchors.append(try CanonicalJSON.decode(LedgerHashAnchor.self, from: Data(line.utf8)))
        }
        return anchors
    }
}

/// A destination whose directory is worked out fresh on every operation.
///
/// # Why resolution is deferred
///
/// iCloud Drive is not reliably *there*. A user signs out; a container that
/// existed at launch returns nil an hour later. A destination that resolved once
/// at startup would keep writing to a stale path, or — worse — silently succeed
/// against a directory that is no longer syncing anywhere, which is an anchor
/// that has stopped being evidence without saying so.
///
/// So the closure runs per operation and is allowed to throw. A failure to
/// resolve becomes a failure to anchor, which the interface reports as
/// ``IntegrityState/anchorOffline(recordCount:)`` — never a fallback write
/// somewhere the user did not choose.
///
/// # Why the closure, rather than an iCloud-specific type here
///
/// Knowing where iCloud lives means knowing whether this process is sandboxed,
/// and that is a `Platform/` question. `Ledger/` is the audit target and reads
/// nothing but Foundation and CryptoKit, so the answer is injected. See
/// `AnchorLocations`.
struct ResolvingAnchorDestination: AnchorDestination {
    let describedLocation: String
    private let resolve: @Sendable () throws -> URL

    init(describedLocation: String, resolve: @escaping @Sendable () throws -> URL) {
        self.describedLocation = describedLocation
        self.resolve = resolve
    }

    private func destination() throws -> DirectoryAnchorDestination {
        DirectoryAnchorDestination(directory: try resolve())
    }

    func write(_ anchor: LedgerHashAnchor) async throws {
        try await destination().write(anchor)
    }

    func latest() async throws -> LedgerHashAnchor? {
        try await destination().latest()
    }

    func history() async throws -> [LedgerHashAnchor] {
        try await destination().history()
    }
}

/// Anchoring turned off.
///
/// Its own type rather than an optional, so "the user switched anchoring off"
/// and "we could not work out where to write" stay different states. They mean
/// opposite things: one is a choice and the other is a fault.
struct DisabledAnchorDestination: AnchorDestination {
    var describedLocation: String { "not anchored" }

    func write(_ anchor: LedgerHashAnchor) async throws {
        _ = anchor
    }

    func latest() async throws -> LedgerHashAnchor? { nil }
    func history() async throws -> [LedgerHashAnchor] { [] }
}
