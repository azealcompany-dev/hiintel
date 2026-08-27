import WidgetKit
import SwiftUI

struct FeedEntry: TimelineEntry {
    let date: Date
    let feed: OpeningsFeed
    let opening: Opening?

    var primaryURL: URL? { opening?.jobURL }
}

struct Provider: TimelineProvider {
    private let rotation: TimeInterval = 8 * 60

    func placeholder(in context: Context) -> FeedEntry {
        let feed = FeedStore.load()
        return FeedEntry(date: Date(), feed: feed, opening: feed.openings.first)
    }

    func getSnapshot(in context: Context, completion: @escaping (FeedEntry) -> Void) {
        let feed = FeedStore.load()
        completion(FeedEntry(date: Date(), feed: feed, opening: feed.openings.first))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeedEntry>) -> Void) {
        Task {
            _ = FeedStore.seedAppGroupIfNeeded()
            _ = await FeedStore.fetchRemote(
                timeout: FeedStore.widgetFetchTimeout,
                reloadOnSuccess: false
            )
            completion(makeTimeline())
        }
    }

    private func makeTimeline() -> Timeline<FeedEntry> {
        let feed = FeedStore.load()
        let now = Date()
        let refreshAfter = now.addingTimeInterval(FeedStore.timelineRefreshInterval)

        if feed.openings.isEmpty {
            let entry = FeedEntry(date: now, feed: feed, opening: nil)
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60)))
        }

        let rotating = Array(feed.openings.prefix(24))
        var entries: [FeedEntry] = []
        for (index, opening) in rotating.enumerated() {
            entries.append(
                FeedEntry(
                    date: now.addingTimeInterval(rotation * Double(index)),
                    feed: feed,
                    opening: opening
                )
            )
        }
        return Timeline(entries: entries, policy: .after(refreshAfter))
    }
}

struct HiringIntelWidget: Widget {
    let kind = FeedStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            HiringIntelWidgetView(entry: entry)
        }
        .configurationDisplayName("HiIntel")
        .description("Live openings from your feed.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

private enum WidgetInk {
    static let bg = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.72)
    static let tertiary = Color.white.opacity(0.5)
}

struct HiringIntelWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: FeedEntry

    var body: some View {
        Group {
            if let opening = entry.opening {
                filled(opening)
                    .widgetURL(opening.jobURL ?? URL(string: "hiringintel://open/\(opening.id)"))
            } else {
                empty
            }
        }
        .padding(family == .systemSmall ? 14 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            WidgetInk.bg
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HiIntel")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetInk.primary)
            Text("No openings yet")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(WidgetInk.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func filled(_ opening: Opening) -> some View {
        let companySize: CGFloat = family == .systemLarge ? 20 : (family == .systemMedium ? 17 : 16)
        let roleSize: CGFloat = family == .systemSmall ? 12 : 13

        VStack(alignment: .leading, spacing: family == .systemSmall ? 5 : 7) {
            Text(opening.company)
                .font(.system(size: companySize, weight: .semibold, design: .default))
                .foregroundStyle(WidgetInk.primary)
                .lineLimit(family == .systemSmall ? 1 : 2)
                .truncationMode(.tail)
            Text(opening.role)
                .font(.system(size: roleSize, weight: .regular))
                .foregroundStyle(WidgetInk.secondary)
                .lineLimit(family == .systemSmall ? 2 : 3)
                .truncationMode(.tail)
            if family != .systemSmall, !opening.location.isEmpty {
                Text(opening.location)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(WidgetInk.tertiary)
                    .lineLimit(2)
            }
            if family == .systemLarge {
                if !opening.lookingFor.isEmpty {
                    Spacer(minLength: 8)
                    Text(opening.lookingFor)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(WidgetInk.secondary)
                        .lineLimit(4)
                }
                if !opening.companyBrief.isEmpty {
                    Text(opening.companyBrief)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(WidgetInk.tertiary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
