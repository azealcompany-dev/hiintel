import SwiftUI
import WidgetKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var feed: OpeningsFeed = .empty

    var body: some View {
        NavigationStack {
            Group {
                if feed.openings.isEmpty {
                    ContentUnavailableView(
                        "No openings",
                        systemImage: "briefcase",
                        description: Text("When feed.json has openings, they appear here and in the widget.")
                    )
                } else {
                    List(feed.openings) { opening in
                        row(for: opening)
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #endif
                }
            }
            .navigationTitle("Hiring Intel")
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refresh()
            } else if phase == .background {
                _ = FeedStore.syncBundleIntoAppGroup()
                FeedStore.reloadTimelines()
            }
        }
    }

    @ViewBuilder
    private func row(for opening: Opening) -> some View {
        if let url = opening.jobURL {
            Link(destination: url) {
                OpeningDetailRow(opening: opening)
            }
            #if os(macOS)
            .foregroundStyle(.primary)
            #endif
        } else {
            OpeningDetailRow(opening: opening)
        }
    }

    private func refresh() {
        _ = FeedStore.syncBundleIntoAppGroup()
        feed = FeedStore.load()
        FeedStore.reloadTimelines()
    }
}

private struct OpeningDetailRow: View {
    let opening: Opening

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(opening.company)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(opening.role)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !opening.location.isEmpty {
                Text(opening.location)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
