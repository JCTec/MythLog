import Foundation

/// Reads the secrets the recorder wrote beside its ledger.
///
/// # Where the HMAC key actually lives
///
/// Not the keychain — the shipping recorder keeps secrets as files under
/// `<ledger directory>/secrets/<account>`, owner-readable only. That matters
/// here because it is what makes "open somebody's ledger and verify it" a thing
/// this app can do at all: the key travels with the ledger, so a directory the
/// user points at is self-sufficient.
///
/// # Read-only, deliberately
///
/// The playground reads ledgers; it does not record. A write path would be code
/// that could damage a real user's install for no benefit, so it does not exist.
/// The shipping `FileSecretStore` has one; this is not that type and should not
/// grow into it.
struct SecretStore: Sendable {
    /// The default account holding the ledger HMAC key, matching
    /// `secrets.hmacKeyAccount` in the config schema.
    static let ledgerHMACKeyAccount = "ledger-hmac-key"

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    init(locations: StorageLocations) {
        self.init(directory: locations.secretsDirectory)
    }

    /// The secret for `account`, or `nil` when there is not one.
    ///
    /// `nil` is a real answer, not a failure: a ledger someone copied without
    /// its `secrets/` directory is readable and unverifiable, and the interface
    /// has to be able to say exactly that rather than refusing to open it.
    func secret(account: String) -> Data? {
        guard let fileName = Self.fileName(forAccount: account) else { return nil }
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        return try? Data(contentsOf: url)
    }

    /// The ledger HMAC key, if it is beside the ledger.
    func ledgerHMACKey(account: String = SecretStore.ledgerHMACKeyAccount) -> Data? {
        guard let data = secret(account: account), !data.isEmpty else { return nil }
        return data
    }

    /// Percent-encodes an account into a safe file name, refusing anything that
    /// could escape the directory.
    ///
    /// The account name comes out of a config file the user can edit, so it is
    /// untrusted input on a path — `..` and `/` are the whole point of this
    /// function existing.
    static func fileName(forAccount account: String) -> String? {
        guard !account.isEmpty else { return nil }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard let encoded = account.addingPercentEncoding(withAllowedCharacters: allowed),
            !encoded.isEmpty,
            encoded != ".", encoded != "..",
            !encoded.contains("/"),
            encoded.utf8.count <= 255
        else {
            return nil
        }
        return encoded
    }
}
