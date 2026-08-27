import Foundation

/// Local saved / applied ids in the App Group. No iCloud.
enum OpeningMarks {
    static let savedKey = "hiintel.savedIDs"
    static let appliedKey = "hiintel.appliedIDs"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: FeedStore.appGroupID)
    }

    static func savedIDs() -> Set<String> { load(savedKey) }
    static func appliedIDs() -> Set<String> { load(appliedKey) }

    static func setSavedIDs(_ ids: Set<String>) { save(ids, key: savedKey) }
    static func setAppliedIDs(_ ids: Set<String>) { save(ids, key: appliedKey) }

    private static func load(_ key: String) -> Set<String> {
        guard let defaults else { return [] }
        if let arr = defaults.stringArray(forKey: key) {
            return Set(arr)
        }
        if let arr = defaults.array(forKey: key) as? [String] {
            return Set(arr)
        }
        return []
    }

    private static func save(_ ids: Set<String>, key: String) {
        defaults?.set(Array(ids).sorted(), forKey: key)
    }
}
