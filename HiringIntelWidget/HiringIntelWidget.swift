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
        _ = FeedStore.syncBundleIntoAppGroup()
        let feed = FeedStore.load()
        let now = Date()

        if feed.openings.isEmpty {
            let entry = FeedEntry(date: now, feed: feed, opening: nil)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }

        var entries: [FeedEntry] = []
        for (index, opening) in feed.openings.enumerated() {
            entries.append(
                FeedEntry(
                    date: now.addingTimeInterval(rotation * Double(index)),
                    feed: feed,
                    opening: opening
                )
            )
        }
        let refresh = now.addingTimeInterval(rotation * Double(feed.openings.count))
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct HiringIntelWidget: Widget {
    let kind = FeedStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            HiringIntelWidgetView(entry: entry)
        }
        .configurationDisplayName("Hiring Intel")
        .description("Live openings from your feed.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct HiringIntelWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: FeedEntry

    var body: some View {
        Group {
            if let opening = entry.opening {
                filled(opening)
                    .widgetURL(URL(string: "hiringintel://open/\(opening.id)"))
            } else {
                empty
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hiring Intel")
                .font(.headline)
            Text("No openings yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func filled(_ opening: Opening) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 6) {
            Text(opening.company)
                .font(family == .systemLarge ? .title3.weight(.semibold) : .headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(opening.role)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if family != .systemSmall, !opening.location.isEmpty {
                Text(opening.location)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            if family == .systemLarge {
                if !opening.lookingFor.isEmpty {
                    Spacer(minLength: 6)
                    Text(opening.lookingFor)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                if !opening.companyBrief.isEmpty {
                    Text(opening.companyBrief)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
