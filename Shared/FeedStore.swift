import Foundation
import WidgetKit

enum FeedStore {
    static let appGroupID = "group.com.azealcompany.hiringintel"
    static let feedFileName = "OpeningsFeed.json"
    static let widgetKind = "com.azealcompany.hiringintel.jobs"
    static let diskFeedPath = "/Users/phlegonjoseph/HiringIntel/feed.json"

    static var appGroupFeedURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(feedFileName)
    }

    static var homeFeedURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("HiringIntel", isDirectory: true)
            .appendingPathComponent("feed.json")
    }

    static var bundledFeedURL: URL? {
        Bundle.main.url(forResource: "feed", withExtension: "json")
    }

    /// Widget appex is App.app/PlugIns/*.appex; host resource is App.app/feed.json.
    static var containingAppFeedURL: URL? {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "appex" else { return nil }
        return bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("feed.json")
    }

    static func load() -> OpeningsFeed {
        let decoder = JSONDecoder()
        let fm = FileManager.default
        var urls: [URL] = []
        if let group = appGroupFeedURL { urls.append(group) }
        urls.append(homeFeedURL)
        urls.append(URL(fileURLWithPath: diskFeedPath))
        if let bundled = bundledFeedURL { urls.append(bundled) }
        if let containing = containingAppFeedURL { urls.append(containing) }

        var seen = Set<String>()
        for url in urls {
            let path = url.path
            if seen.contains(path) { continue }
            seen.insert(path)
            guard fm.fileExists(atPath: path), let data = try? Data(contentsOf: url) else { continue }
            if let feed = try? decoder.decode(OpeningsFeed.self, from: data) {
                return feed
            }
        }
        return .empty
    }

    /// Prefer live Builder file on disk, then bundled snapshot. Copy into the App Group.
    @discardableResult
    static func syncBundleIntoAppGroup() -> Bool {
        guard let dest = appGroupFeedURL else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        var sources: [URL] = []
        let home = homeFeedURL
        let explicit = URL(fileURLWithPath: diskFeedPath)
        if fm.fileExists(atPath: home.path) { sources.append(home) }
        if explicit.path != home.path, fm.fileExists(atPath: explicit.path) { sources.append(explicit) }
        if let bundled = bundledFeedURL { sources.append(bundled) }

        guard let src = sources.first(where: { fm.fileExists(atPath: $0.path) }) else { return false }
        guard let data = try? Data(contentsOf: src) else { return false }
        do {
            if let existing = try? Data(contentsOf: dest), existing == data {
                return true
            }
            try data.write(to: dest, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
