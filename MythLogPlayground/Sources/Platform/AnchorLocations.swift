import Foundation

/// Reads the iCloud ubiquity container.
///
/// Injectable because the real call blocks and needs a signed-in account, and
/// because both branches — present and absent — have to be testable. A test that
/// can only exercise "iCloud is there" never exercises the branch that matters.
protocol UbiquityContainerResolving: Sendable {
    func containerURL(forIdentifier identifier: String?) -> URL?
}

struct SystemUbiquityContainerResolver: UbiquityContainerResolving {
    func containerURL(forIdentifier identifier: String?) -> URL? {
        // A fresh `FileManager`: `.default` is shared process-wide and not
        // `Sendable`, and this call is made from arbitrary isolation.
        FileManager().url(forUbiquityContainerIdentifier: identifier)
    }
}

/// Always resolves to a fixed URL, or to nothing. For tests, and for describing
/// a machine that is signed out.
struct FixedUbiquityContainerResolver: UbiquityContainerResolving {
    var url: URL?

    func containerURL(forIdentifier identifier: String?) -> URL? { url }
}

/// Where anchors go, for each kind of destination the user can pick.
///
/// # Why this is in `Platform/` and not `Ledger/`
///
/// Working out where iCloud lives means knowing whether this process is
/// sandboxed, which is a platform question. `Ledger/` is the audit target and
/// reads nothing but Foundation and CryptoKit — a rule
/// `Scripts/check-layering.sh` enforces — so it takes a resolved location rather
/// than working one out. See ``ResolvingAnchorDestination``.
///
/// # There is no fallback, on purpose
///
/// When iCloud cannot be resolved this throws. It does not quietly write to
/// `~/Library` instead. An anchor in the wrong place is worse than no anchor:
/// it looks like the protection is on, and the whole value of an anchor is
/// being somewhere the adversary cannot reach.
struct AnchorLocations: Sendable {
    /// The kinds of place this layer knows how to find.
    ///
    /// Its own vocabulary rather than the config schema's `AnchorDestinationKind`:
    /// `Platform/` may reference `Primitives/` and nothing else, and the mapping
    /// belongs one layer up where both are visible. It is also the honest split —
    /// this type answers "where is iCloud", not "what did the user configure".
    enum Kind: Equatable, Sendable {
        case iCloudDrive
        case directory
    }

    static let iCloudContainerIdentifier = "iCloud.com.jctec.mythlog"

    var environment: SandboxEnvironment
    var ubiquity: any UbiquityContainerResolving
    /// The unsandboxed iCloud Drive folder, resolved by ``StorageLocations`` —
    /// the only type permitted to ask where home is.
    var iCloudDriveDirectory: URL

    init(
        environment: SandboxEnvironment = .current(),
        ubiquity: any UbiquityContainerResolving = SystemUbiquityContainerResolver(),
        iCloudDriveDirectory: URL = StorageLocations.iCloudDriveDirectory()
    ) {
        self.environment = environment
        self.ubiquity = ubiquity
        self.iCloudDriveDirectory = iCloudDriveDirectory
    }

    /// The directory for `kind`.
    ///
    /// - Parameter chosenDirectory: the configured path, used verbatim for
    ///   ``Kind/directory``.
    ///
    /// Blocks on the iCloud lookup when sandboxed, so callers resolve off the
    /// main actor — which ``ResolvingAnchorDestination`` does by construction,
    /// since it resolves inside an `async` call.
    func directory(for kind: Kind, chosenDirectory: String?) throws -> URL {
        switch kind {
        case .directory:
            guard let chosenDirectory, !chosenDirectory.isEmpty else {
                throw PlatformError.anchorDestinationUnavailable(
                    detail: "no anchor directory has been chosen")
            }
            return URL(fileURLWithPath: chosenDirectory)

        case .iCloudDrive:
            guard environment.isSandboxed else {
                // Unsandboxed: the visible CloudDocs folder, so the user can
                // find the anchors in Finder and copy one somewhere safer.
                return iCloudDriveDirectory
            }
            guard let container = ubiquity.containerURL(forIdentifier: Self.iCloudContainerIdentifier) else {
                throw PlatformError.anchorDestinationUnavailable(
                    detail: "iCloud Drive is signed out, or the ubiquity container "
                        + "'\(Self.iCloudContainerIdentifier)' is unavailable"
                )
            }
            return
                container
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("MythLog", isDirectory: true)
        }
    }

    /// Where anchors go, said in a form a person can check — including when it
    /// cannot currently be resolved.
    ///
    /// Never throws. An unattributable failure is the thing this whole layer
    /// exists to prevent: "anchoring is off" and "anchoring is aimed at a place
    /// that is not currently there" are different sentences.
    func describe(_ kind: Kind, chosenDirectory: String?) -> String {
        do {
            return try directory(for: kind, chosenDirectory: chosenDirectory).path
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}
