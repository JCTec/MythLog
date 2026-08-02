import Foundation

public enum AgentFactory {
    public static func hmacKey(for config: MythLogConfig, secretStore: any SecretStore) throws -> Data {
        if let key = try secretStore.readSecret(account: config.secrets.hmacKeyAccount) {
            return key
        }

        if config.secrets.allowDevelopmentFallbackKey {
            return SecretMaterial.developmentHMACKey(identity: config.identity)
        }

        throw MythLogError.missingHMACKey(account: config.secrets.hmacKeyAccount)
    }

    public static func hmacKeyOffMain(for config: MythLogConfig, secretStore: any SecretStore) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try hmacKey(for: config, secretStore: secretStore)
        }.value
    }

    @discardableResult
    public static func ensureHMACKey(for config: MythLogConfig, secretStore: any SecretStore) throws -> Data {
        if let key = try secretStore.readSecret(account: config.secrets.hmacKeyAccount) {
            return key
        }

        let key = try SecretMaterial.randomKey()
        try secretStore.writeSecret(key, account: config.secrets.hmacKeyAccount)
        return key
    }

    @MainActor
    public static func makeRuntime(config: MythLogConfig, secretStore: any SecretStore) throws -> MythLogAgentRuntime {
        let key = try hmacKey(for: config, secretStore: secretStore)
        return try MythLogAgentRuntime(config: config, hmacKey: key)
    }
}
