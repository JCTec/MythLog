import Foundation

/// Hand-written `Codable` so that unmodelled sections survive.
///
/// The synthesised conformance would decode the six known keys and drop the
/// rest. This decodes the known keys, sweeps everything else into
/// ``EngineConfig/unmodelled``, and re-emits both — so loading and saving a
/// config written by a newer build returns it unchanged.
extension EngineConfig: Codable {
    /// A key known only at runtime, which is what reading unknown sections
    /// requires.
    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)

        func decode<T: Decodable>(_ type: T.Type, _ key: String) throws -> T? {
            try container.decodeIfPresent(type, forKey: DynamicKey(stringValue: key))
        }

        // Absent sections take this build's defaults — except `storage`, where
        // absence stays absence. See the note on `EngineConfig`.
        schemaVersion = try decode(Int.self, "schemaVersion") ?? 1
        identity = try decode(AgentIdentity.self, "identity") ?? AgentIdentity()
        storage = try decode(StorageConfig.self, "storage")
        secrets = try decode(SecretConfig.self, "secrets") ?? SecretConfig()
        heartbeat = try decode(HeartbeatConfig.self, "heartbeat") ?? HeartbeatConfig()
        hashAnchor = try decode(HashAnchorConfig.self, "hashAnchor") ?? HashAnchorConfig()

        var extras = [String: JSONValue]()
        for key in container.allKeys where !Self.modelledKeys.contains(key.stringValue) {
            extras[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        unmodelled = extras
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)

        try container.encode(schemaVersion, forKey: DynamicKey(stringValue: "schemaVersion"))
        try container.encode(identity, forKey: DynamicKey(stringValue: "identity"))
        // `encodeIfPresent`: an absent storage section must stay absent, not
        // reappear as an empty object.
        try container.encodeIfPresent(storage, forKey: DynamicKey(stringValue: "storage"))
        try container.encode(secrets, forKey: DynamicKey(stringValue: "secrets"))
        try container.encode(heartbeat, forKey: DynamicKey(stringValue: "heartbeat"))
        try container.encode(hashAnchor, forKey: DynamicKey(stringValue: "hashAnchor"))

        for (key, value) in unmodelled {
            try container.encode(value, forKey: DynamicKey(stringValue: key))
        }
    }
}

// MARK: - Files

extension EngineConfig {
    /// Reads a config file.
    ///
    /// Throws rather than returning defaults. A config that cannot be read is
    /// not a config full of defaults, and treating it as one is how a
    /// misconfigured install looks healthy — the failure mode this whole layer
    /// exists to prevent.
    ///
    /// Synchronous: it is one small file, read once at launch, and an `async`
    /// signature would suggest a wait that does not happen.
    static func load(from url: URL) throws -> EngineConfig {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError.unreadable(path: url.path, underlying: String(describing: error))
        }

        do {
            return try CanonicalJSON.decode(EngineConfig.self, from: data)
        } catch {
            throw ConfigError.malformed(path: url.path, underlying: String(describing: error))
        }
    }

    /// Writes the config as the shipping recorder writes it: pretty-printed,
    /// keys sorted, slashes unescaped, owner-only permissions.
    ///
    /// Sorted keys are what makes the round trip byte-exact regardless of the
    /// order `unmodelled` happens to enumerate in.
    func write(to url: URL, fileManager: sending FileManager = FileManager()) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: url, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func encoded() throws -> Data {
        try CanonicalJSON.makeReadableEncoder().encode(self)
    }
}
