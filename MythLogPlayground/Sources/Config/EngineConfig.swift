import Foundation

/// The on-disk configuration, as a document rather than a settings object.
///
/// # Storage paths are not resolved from here. Ever.
///
/// ``StorageConfig`` is `Optional`, its fields are `Optional`, and none of them
/// have a default. That is the whole point. In 1.0.0 a bare `MythLogConfig()`
/// carried `~/Library/Application Support/MythLog/events.jsonl`, and anything
/// that constructed one and read `.storage.ledgerPath` got a path that was
/// correct unsandboxed and silently wrong under the sandbox, where `~` expands
/// to a process-private container. There was no way to tell "the user configured
/// this path" apart from "nobody configured anything and this is the default".
///
/// Here, absence is absence. A config with no `storage` section says nothing
/// about where the ledger is, and the answer comes from
/// ``StorageLocations`` — which is container-aware and cannot produce a tilde.
/// `Scripts/check-layering.sh` fails the build if anything else tries.
///
/// # Unmodelled sections survive the round trip
///
/// This build models `schemaVersion`, `identity`, `storage`, `secrets`,
/// `heartbeat`, and `hashAnchor`. Everything else the recorder writes —
/// `session`, `filesystem`, `unifiedLog`, `notifications`, `telegram`,
/// `remoteCheckpoint`, `rules` — belongs to waves that have not landed, and is
/// preserved verbatim in ``unmodelled`` rather than dropped.
///
/// That is stronger than the shipping app, whose `Codable` conformance discards
/// any key it does not know: load and save there and a section written by a
/// newer build disappears. The user's file is theirs, and a viewer has no
/// business shrinking it.
struct EngineConfig: Equatable, Sendable {
    var schemaVersion: Int
    var identity: AgentIdentity
    /// Absent means "not configured", never "use the default path".
    var storage: StorageConfig?
    var secrets: SecretConfig
    var heartbeat: HeartbeatConfig
    var hashAnchor: HashAnchorConfig

    /// Every top-level key this build does not model, kept exactly as written.
    var unmodelled: [String: JSONValue]

    init(
        schemaVersion: Int = 1,
        identity: AgentIdentity = .init(),
        storage: StorageConfig? = nil,
        secrets: SecretConfig = .init(),
        heartbeat: HeartbeatConfig = .init(),
        hashAnchor: HashAnchorConfig = .init(),
        unmodelled: [String: JSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.storage = storage
        self.secrets = secrets
        self.heartbeat = heartbeat
        self.hashAnchor = hashAnchor
        self.unmodelled = unmodelled
    }

    /// The keys this build understands. Anything else lands in ``unmodelled``.
    static let modelledKeys: Set<String> = [
        "schemaVersion", "identity", "storage", "secrets", "heartbeat", "hashAnchor",
    ]
}

// MARK: - Sections

struct AgentIdentity: Codable, Equatable, Sendable {
    var deviceID: String
    var displayName: String

    init(deviceID: String = "", displayName: String = "") {
        self.deviceID = deviceID
        self.displayName = displayName
    }
}

/// What the user wrote about storage, if anything.
///
/// Every field is `Optional` with no default, so "absent" and "configured"
/// remain distinguishable. Nothing here is resolved into a URL — see the note on
/// ``EngineConfig``.
struct StorageConfig: Codable, Equatable, Sendable {
    var ledgerPath: String?
    var outboxDirectory: String?
    var runtimeDirectory: String?
    var spoolDirectory: String?
    /// Size at which the active segment rotates. `nil` disables rotation, which
    /// makes the active file the entire history — the case that makes streaming
    /// non-negotiable.
    var maxLedgerFileBytes: Int?

    init(
        ledgerPath: String? = nil,
        outboxDirectory: String? = nil,
        runtimeDirectory: String? = nil,
        spoolDirectory: String? = nil,
        maxLedgerFileBytes: Int? = nil
    ) {
        self.ledgerPath = ledgerPath
        self.outboxDirectory = outboxDirectory
        self.runtimeDirectory = runtimeDirectory
        self.spoolDirectory = spoolDirectory
        self.maxLedgerFileBytes = maxLedgerFileBytes
    }

    /// Every configured path with the field it came from, for validation.
    var configuredPaths: [(field: String, path: String)] {
        [
            ("storage.ledgerPath", ledgerPath),
            ("storage.outboxDirectory", outboxDirectory),
            ("storage.runtimeDirectory", runtimeDirectory),
            ("storage.spoolDirectory", spoolDirectory),
        ].compactMap { field, path in path.map { (field, $0) } }
    }
}

struct SecretConfig: Codable, Equatable, Sendable {
    var hmacKeyAccount: String
    /// A build that will invent an HMAC key rather than fail. Never true in a
    /// shipping build: a ledger signed with a key the attacker can also derive
    /// proves nothing.
    var allowDevelopmentFallbackKey: Bool

    init(hmacKeyAccount: String = "ledger-hmac-key", allowDevelopmentFallbackKey: Bool = false) {
        self.hmacKeyAccount = hmacKeyAccount
        self.allowDevelopmentFallbackKey = allowDevelopmentFallbackKey
    }
}

/// How often the recorder writes proof that it was alive.
///
/// This is what makes coverage gaps detectable *from absence*: a graceful stop
/// writes a record, but a force-quit, a crash, or a power cut writes nothing at
/// all. The only evidence left is the heartbeat that never arrived.
struct HeartbeatConfig: Codable, Equatable, Sendable {
    var enabled: Bool
    var intervalSeconds: TimeInterval
    var checkpointEveryHeartbeats: Int

    init(enabled: Bool = true, intervalSeconds: TimeInterval = 60, checkpointEveryHeartbeats: Int = 5) {
        self.enabled = enabled
        self.intervalSeconds = intervalSeconds
        self.checkpointEveryHeartbeats = checkpointEveryHeartbeats
    }

    /// How long a silence has to be before it is a gap rather than a quiet
    /// stretch. Three missed heartbeats: one can be lost to scheduling, two to a
    /// slow wake, three means the recorder was not running.
    static let missedHeartbeatsForGap = 3.0

    var gapThreshold: TimeInterval { intervalSeconds * Self.missedHeartbeatsForGap }
}

/// Which kind of destination the user picked.
///
/// Named `…Kind` because ``AnchorDestination`` is now the protocol that *does*
/// the writing. This is the schema value naming a choice; that is the thing
/// carrying it out. The raw values are unchanged, so every config already on
/// disk decodes exactly as before.
enum AnchorDestinationKind: String, Codable, Equatable, Sendable {
    /// The environment-aware iCloud location. The default, because an anchor is
    /// only evidence if it lives outside the Mac it describes.
    case iCloudDrive
    /// A literal directory, for users who pin anchors somewhere specific.
    case directory
}

struct HashAnchorConfig: Codable, Equatable, Sendable {
    var enabled: Bool
    var directory: String?
    var anchorEveryHeartbeats: Int
    var destination: AnchorDestinationKind

    init(
        enabled: Bool = true,
        directory: String? = nil,
        anchorEveryHeartbeats: Int = 5,
        destination: AnchorDestinationKind = .iCloudDrive
    ) {
        self.enabled = enabled
        self.directory = directory
        self.anchorEveryHeartbeats = anchorEveryHeartbeats
        self.destination = destination
    }

    enum CodingKeys: String, CodingKey {
        case enabled, directory, anchorEveryHeartbeats, destination
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        directory = try container.decodeIfPresent(String.self, forKey: .directory)
        anchorEveryHeartbeats = try container.decodeIfPresent(Int.self, forKey: .anchorEveryHeartbeats) ?? 5
        // A config predating this field kept writing to `directory`, so an absent
        // `destination` must decode as `.directory` — byte-for-byte the old
        // behaviour. Freshly created configs default to `.iCloudDrive`.
        destination = try container.decodeIfPresent(AnchorDestinationKind.self, forKey: .destination) ?? .directory
    }
}
