import SwiftUI

// The first-run page in the states a person actually meets it in.

/// Nothing installed. The common case for a new machine, and the one where the
/// two-column promise has to carry the whole screen on its own.
#Preview("Welcome — no ledger found") {
    WelcomePage(
        candidates: [],
        samples: MockTimelineSource.samples,
        lastOpenedPath: nil,
        problem: nil,
        onOpen: { _ in },
        onOpenSample: { _ in },
        onBrowse: {}
    )
    .frame(width: 1000, height: 900)
    .preferredColorScheme(.dark)
}

/// A ledger was found. It is offered, not opened — the sentence above the list
/// says so explicitly, because "we found your history and put it on screen" is
/// the behaviour this design is refusing.
#Preview("Welcome — ledger found") {
    WelcomePage(
        candidates: [.previewInstalled],
        samples: MockTimelineSource.samples,
        lastOpenedPath: LedgerCandidate.previewInstalled.ledgerURL.path,
        problem: nil,
        onOpen: { _ in },
        onOpenSample: { _ in },
        onBrowse: {}
    )
    .frame(width: 1000, height: 900)
    .preferredColorScheme(.dark)
}

/// A ledger with no key beside it: readable, unverifiable, and offered anyway
/// with the bad news on the row. Hiding it would be the less honest option.
#Preview("Welcome — ledger without a key, and a failed open") {
    WelcomePage(
        candidates: [.previewInstalled, .previewNoKey],
        samples: MockTimelineSource.samples,
        lastOpenedPath: nil,
        problem: "That ledger could not be opened: /Volumes/Backup/events.jsonl is not a readable file.",
        onOpen: { _ in },
        onOpenSample: { _ in },
        onBrowse: {}
    )
    .frame(width: 1000, height: 900)
    .preferredColorScheme(.dark)
}

extension LedgerCandidate {
    /// A plausible installed ledger. Never touches the disk — previews must not
    /// depend on what happens to be on the machine rendering them.
    static var previewInstalled: LedgerCandidate {
        LedgerCandidate(
            id: "/preview/MythLog/events.jsonl",
            origin: .installed(.appGroupContainer(group: SharedContainer.groupIdentifier)),
            ledgerURL: URL(fileURLWithPath: "/preview/MythLog/events.jsonl"),
            hmacKey: Data("preview".utf8),
            heartbeatInterval: 60,
            title: "MythLog ledger",
            detail: "/preview/MythLog · Recorded by Juan’s MacBook Pro.",
            byteSize: 61_204_992
        )
    }

    static var previewNoKey: LedgerCandidate {
        LedgerCandidate(
            id: "/Volumes/Backup/events.jsonl",
            origin: .chosen,
            ledgerURL: URL(fileURLWithPath: "/Volumes/Backup/events.jsonl"),
            hmacKey: nil,
            heartbeatInterval: 60,
            title: "Backup",
            detail: "/Volumes/Backup · No key found beside it — readable, but nothing can be verified.",
            byteSize: 4_194_304
        )
    }
}
