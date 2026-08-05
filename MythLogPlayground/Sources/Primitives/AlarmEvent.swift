import Foundation

/// How loudly an event asks to be noticed. Ordered, so rules can express
/// "at least a warning" without enumerating cases.
enum AlarmSeverity: String, Codable, CaseIterable, Comparable, Sendable {
    case debug
    case info
    case notice
    case warning
    case critical

    private var rank: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .notice: 2
        case .warning: 3
        case .critical: 4
        }
    }

    static func < (lhs: AlarmSeverity, rhs: AlarmSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// One observed event, exactly as it was written to the ledger.
///
/// # The schema is additive-only, permanently.
///
/// A ledger record's hash is an HMAC over the canonical JSON of *the whole
/// event* (`LedgerHashChain.hash(event:previousHash:key:)`), and verification
/// re-encodes each stored event to recompute that hash. The encoded bytes are
/// therefore part of the ledger's contract, not an implementation detail.
///
/// The consequence is absolute and easy to trip over:
///
/// > **Adding a non-optional field retroactively breaks verification of every
/// > ledger every user already has.**
///
/// A record written last year has no value for the new field. Decoding it
/// substitutes the new field's default; re-encoding then emits a key that was
/// not present when the HMAC was computed; the hash no longer matches; the
/// record is reported as tampered with. Not "some records" — every record from
/// the first one onwards, because the previous-hash chain fails at record 1 and
/// every record after it. The user's history stops being trustworthy because of
/// a schema change, which is the single worst failure this product can have.
///
/// The rules that follow from that, without exception:
///
/// 1. **New fields are `Optional` and default to `nil`.** A `nil` optional is
///    omitted by `JSONEncoder`, so the canonical bytes of every historical
///    record are unchanged.
/// 2. **Never rename a field.** The key is in the hashed bytes.
/// 3. **Never reorder.** `.sortedKeys` makes declaration order irrelevant to the
///    output — which is exactly why nobody should ever rely on it staying that
///    way by rearranging the declarations.
/// 4. **Never change a field's type**, including widening `Int` to `Double`;
///    `1` and `1.0` are different bytes.
/// 5. **Never remove a field.** Deprecate it and keep encoding it.
///
/// If a field genuinely cannot be optional, the schema has changed
/// incompatibly. That needs a new record type carried alongside the old one and
/// a migration that re-anchors, not an edit here.
///
/// `AlarmEvent` is a value type with `Sendable` stored properties, so its
/// `Sendable` conformance is implicit — it crosses from the ledger actor to the
/// main actor with no ceremony and no reference semantics to reason about.
struct AlarmEvent: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var observedAt: Date
    var host: String
    var source: String
    var name: String
    var severity: AlarmSeverity
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        observedAt: Date = .now,
        host: String = AlarmEvent.currentHost,
        source: String,
        name: String,
        severity: AlarmSeverity = .info,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.observedAt = observedAt
        self.host = host
        self.source = source
        self.name = name
        self.severity = severity
        self.metadata = metadata
    }

    /// Matches the shipping recorder's default so events written by either
    /// process carry the same host string.
    static var currentHost: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    /// `source.name`, the identity the rules and the UI both key on.
    var qualifiedName: String { "\(source).\(name)" }
}
