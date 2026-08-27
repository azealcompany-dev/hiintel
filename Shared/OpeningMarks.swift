import Foundation

extension Notification.Name {
    static let hiintelOpenJob = Notification.Name("hiintelOpenJob")
}

/// Local reader state in the App Group. No iCloud.
enum OpeningMarks {
    static let savedKey = "hiintel.savedIDs"
    static let appliedKey = "hiintel.appliedIDs"
    static let pinnedKey = "hiintel.pinnedCompanies"
    static let mutedKey = "hiintel.mutedCompanies"
    static let lastAppOpenKey = "hiintel.lastAppOpen"
    static let snapshotsKey = "hiintel.openingSnapshots"
    static let notesKey = "hiintel.notes"
    static let datesKey = "hiintel.followDates"
    static let followUpDoneKey = "hiintel.followUpDone"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: FeedStore.appGroupID)
    }

    static func savedIDs() -> Set<String> { loadSet(savedKey) }
    static func appliedIDs() -> Set<String> { loadSet(appliedKey) }
    static func pinnedCompanies() -> Set<String> { loadSet(pinnedKey) }
    static func mutedCompanies() -> Set<String> { loadSet(mutedKey) }
    static func followUpDoneIDs() -> Set<String> { loadSet(followUpDoneKey) }

    static func setSavedIDs(_ ids: Set<String>) { saveSet(ids, key: savedKey) }
    static func setAppliedIDs(_ ids: Set<String>) { saveSet(ids, key: appliedKey) }
    static func setPinnedCompanies(_ names: Set<String>) { saveSet(names, key: pinnedKey) }
    static func setMutedCompanies(_ names: Set<String>) { saveSet(names, key: mutedKey) }
    static func setFollowUpDoneIDs(_ ids: Set<String>) { saveSet(ids, key: followUpDoneKey) }

    static var lastAppOpen: Date? {
        get { defaults?.object(forKey: lastAppOpenKey) as? Date }
        set { defaults?.set(newValue, forKey: lastAppOpenKey) }
    }

    static func notes() -> [String: String] { loadStringMap(notesKey) }
    static func dates() -> [String: String] { loadStringMap(datesKey) }

    static func setNote(_ note: String, for id: String) {
        var map = notes()
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            map.removeValue(forKey: id)
        } else {
            map[id] = trimmed
        }
        saveStringMap(map, key: notesKey)
    }

    static func setDate(_ iso: String?, for id: String) {
        var map = dates()
        if let iso, !iso.isEmpty {
            map[id] = iso
        } else {
            map.removeValue(forKey: id)
        }
        saveStringMap(map, key: datesKey)
    }

    static func snapshots() -> [String: Opening] {
        guard let data = defaults?.data(forKey: snapshotsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Opening].self, from: data)) ?? [:]
    }

    static func saveSnapshot(_ opening: Opening) {
        var map = snapshots()
        var stored = opening
        stored.isClosed = false
        map[opening.id] = stored
        if let data = try? JSONEncoder().encode(map) {
            defaults?.set(data, forKey: snapshotsKey)
        }
    }

    static func newCount(in feed: OpeningsFeed, since lastOpen: Date?) -> Int {
        guard let lastOpen else { return 0 }
        return feed.openings.filter { opening in
            guard let posted = opening.postedDate else { return false }
            return posted > lastOpen
        }.count
    }

    static func newTodayCount(in feed: OpeningsFeed) -> Int {
        let cal = Calendar.current
        return feed.openings.filter { opening in
            guard let posted = opening.postedDate else { return false }
            return cal.isDateInToday(posted)
        }.count
    }

    static func orderedForWidget(_ openings: [Opening]) -> [Opening] {
        let pinned = pinnedCompanies()
        let saved = savedIDs()
        return openings.sorted { a, b in
            let ra = pinned.contains(a.company) ? 0 : (saved.contains(a.id) ? 1 : 2)
            let rb = pinned.contains(b.company) ? 0 : (saved.contains(b.id) ? 1 : 2)
            if ra != rb { return ra < rb }
            if a.postedAt != b.postedAt { return a.postedAt > b.postedAt }
            return a.company.localizedCaseInsensitiveCompare(b.company) == .orderedAscending
        }
    }

    private static func loadSet(_ key: String) -> Set<String> {
        guard let defaults else { return [] }
        if let arr = defaults.stringArray(forKey: key) { return Set(arr) }
        if let arr = defaults.array(forKey: key) as? [String] { return Set(arr) }
        return []
    }

    private static func saveSet(_ ids: Set<String>, key: String) {
        defaults?.set(Array(ids).sorted(), forKey: key)
    }

    private static func loadStringMap(_ key: String) -> [String: String] {
        defaults?.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private static func saveStringMap(_ map: [String: String], key: String) {
        defaults?.set(map, forKey: key)
    }
}
