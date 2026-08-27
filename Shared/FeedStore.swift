import Foundation
import WidgetKit

enum FeedStore {
    static let appGroupID = "group.com.azealcompany.hiringintel"
    static let feedFileName = "OpeningsFeed.json"
    static let widgetKind = "com.azealcompany.hiringintel.jobs"
    static let diskFeedPath = "/Users/phlegonjoseph/HiringIntel/feed.json"
    static let remoteFeedURL = URL(string: "https://raw.githubusercontent.com/azealcompany-dev/hiintel-feed/main/feed.json")!
    static let widgetFetchTimeout: TimeInterval = 6
    static let hostFetchTimeout: TimeInterval = 10
    static let timelineRefreshInterval: TimeInterval = 30 * 60

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
        if let bundled = bundledFeedURL { urls.append(bundled) }
        if let containing = containingAppFeedURL { urls.append(containing) }
        urls.append(homeFeedURL)
        urls.append(URL(fileURLWithPath: diskFeedPath))

        var seen = Set<String>()
        for url in urls {
            let path = url.path
            if seen.contains(path) { continue }
            seen.insert(path)
            guard fm.fileExists(atPath: path), let data = try? Data(contentsOf: url) else { continue }
            if let feed = try? decoder.decode(OpeningsFeed.self, from: data), !feed.openings.isEmpty {
                return feed
            }
        }
        return .empty
    }

    @discardableResult
    static func cacheData(_ data: Data) -> Bool {
        guard let dest = appGroupFeedURL else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
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

    /// Seed App Group from bundled/disk feed only when the cache is missing.
    @discardableResult
    static func seedAppGroupIfNeeded() -> Bool {
        guard let dest = appGroupFeedURL else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing = try? Data(contentsOf: dest),
           (try? JSONDecoder().decode(OpeningsFeed.self, from: existing))?.openings.isEmpty == false {
            return true
        }
        var sources: [URL] = []
        if let bundled = bundledFeedURL { sources.append(bundled) }
        if let containing = containingAppFeedURL { sources.append(containing) }
        let home = homeFeedURL
        let explicit = URL(fileURLWithPath: diskFeedPath)
        if fm.fileExists(atPath: home.path) { sources.append(home) }
        if explicit.path != home.path, fm.fileExists(atPath: explicit.path) { sources.append(explicit) }
        guard let src = sources.first(where: { fm.fileExists(atPath: $0.path) }) else { return false }
        guard let data = try? Data(contentsOf: src) else { return false }
        return cacheData(data)
    }

    /// Kept for older call sites. Does not clobber a live remote cache.
    @discardableResult
    static func syncBundleIntoAppGroup() -> Bool {
        seedAppGroupIfNeeded()
    }

    /// Pull GitHub raw into the App Group. Returns the decoded feed on success.
    @discardableResult
    static func fetchRemote(timeout: TimeInterval, reloadOnSuccess: Bool) async -> OpeningsFeed? {
        var request = URLRequest(url: remoteFeedURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let feed = try JSONDecoder().decode(OpeningsFeed.self, from: data)
            guard !feed.openings.isEmpty else { return nil }
            _ = cacheData(data)
            if reloadOnSuccess {
                reloadTimelines()
            }
            return feed
        } catch {
            return nil
        }
    }

    static func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
