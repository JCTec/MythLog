import Foundation

/// A filter someone named and kept.
struct SavedFilter: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var name: String
    var filter: EventFilter
    var createdAt: Date

    init(id: UUID = UUID(), name: String, filter: EventFilter, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.filter = filter
        self.createdAt = createdAt
    }

    /// `“Ignore builds”, saved 3 August` — the sentence the launch notice needs.
    ///
    /// A filter the user does not remember setting is the failure this feature
    /// can cause, and the date is most of the cure: a name alone invites "yes,
    /// that sounds like something I'd have done", which is not recognition.
    var attribution: String {
        "“\(name)”, saved \(createdAt.formatted(.dateTime.day().month(.wide)))"
    }
}

/// Where saved filters and the active one are kept between launches.
///
/// # Restoring a filter is dangerous, and it is still the right behaviour
///
/// A quiet timeline is what this app is for. A filter restored from last week
/// that nobody remembers setting turns a quiet timeline into a lie, and it does
/// it in the one place the lie is most convincing — the user is looking at their
/// own history and it looks fine.
///
/// The alternative, starting unfiltered every launch, is worse in its own way:
/// somebody who set up "Ignore builds" because their ledger is 90% build noise
/// gets the noise back every morning and eventually stops opening the app.
///
/// So the filter is restored *and* announced, loudly and permanently, until it
/// is acknowledged or cleared — see ``MainPage/Model/restoredFilter``. The
/// announcement is not a nicety here; it is the thing that makes restoring
/// defensible at all.
///
/// Contrast ``OpenedLedgerMemory``, which deliberately does **not** reopen: the
/// asymmetry is intentional. Reopening a ledger puts somebody's history on a
/// screen in front of whoever is in the room. Restoring a filter does not
/// disclose anything; it only risks concealing, which an announcement can
/// address and a closed window cannot.
struct SavedFilterStore: Sendable {
    private static let filtersKey = "com.jctec.mythlog.playground.savedFilters"
    private static let activeKey = "com.jctec.mythlog.playground.activeFilter"

    /// Which defaults to use. A suite name rather than a `UserDefaults`, because
    /// `UserDefaults` is not `Sendable`; instances are made inside each call, as
    /// ``OpenedLedgerMemory`` does, on a property list the system already holds.
    var suiteName: String?

    /// # Why the container override decides the suite
    ///
    /// Saved filters belong to an *install*, and
    /// ``SharedContainer/containerOverrideKey`` is how this codebase already says
    /// "this process is pointed at a different install than the one on this Mac".
    /// The test scheme sets it for exactly that reason — see the note on
    /// `SharedContainer`, and the README's account of what happens when a test
    /// run reads the developer's real state.
    ///
    /// Without this, running the suite would read whatever filters the developer
    /// had saved, restore one into every `MainPage.Model` a test builds, and
    /// write its own back over them. A test that fails because of a filter
    /// somebody set last week is the same failure this feature is about, aimed at
    /// the wrong victim.
    ///
    /// The path is sanitised because a suite name becomes a file name, and a path
    /// contains separators.
    init(suiteName: String? = nil) {
        if let suiteName {
            self.suiteName = suiteName
            return
        }
        let override = ProcessInfo.processInfo.environment[SharedContainer.containerOverrideKey]
        self.suiteName = override.flatMap { path in
            // Empty means "no install here" — a real state, and still not the
            // developer's own defaults.
            guard !path.isEmpty else { return "com.jctec.mythlog.playground.filters.no-install" }
            let sanitised = String(
                path.map { $0.isLetter || $0.isNumber ? $0 : "-" }.suffix(80))
            return "com.jctec.mythlog.playground.filters.\(sanitised)"
        }
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    // MARK: - The named ones

    func saved() -> [SavedFilter] {
        guard let data = defaults.data(forKey: Self.filtersKey) else { return [] }
        // A decode failure means a stored shape this build does not understand.
        // Returning an empty list is right — it is honest about what this build
        // can offer, and it never silently applies something it misread.
        return (try? JSONDecoder().decode([SavedFilter].self, from: data)) ?? []
    }

    func save(_ filter: SavedFilter) {
        var all = saved().filter { $0.id != filter.id && $0.name != filter.name }
        all.append(filter)
        write(all)
    }

    func delete(_ id: SavedFilter.ID) {
        write(saved().filter { $0.id != id })
    }

    private func write(_ all: [SavedFilter]) {
        guard let data = try? JSONEncoder().encode(all.sorted { $0.name < $1.name }) else { return }
        defaults.set(data, forKey: Self.filtersKey)
    }

    // MARK: - The active one

    /// What was on screen when the app was last closed, and the saved filter it
    /// came from when it came from one.
    struct Active: Hashable, Sendable, Codable {
        var filter: EventFilter
        /// `nil` for a filter the user built by hand and never named.
        var savedAs: SavedFilter?
    }

    func active() -> Active? {
        guard let data = defaults.data(forKey: Self.activeKey) else { return nil }
        return try? JSONDecoder().decode(Active.self, from: data)
    }

    func rememberActive(_ active: Active?) {
        guard let active, active.filter.isFiltering else {
            defaults.removeObject(forKey: Self.activeKey)
            return
        }
        guard let data = try? JSONEncoder().encode(active) else { return }
        defaults.set(data, forKey: Self.activeKey)
    }
}
