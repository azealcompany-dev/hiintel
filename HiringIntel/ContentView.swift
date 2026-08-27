import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var feed: OpeningsFeed = .empty

    var body: some View {
        NavigationStack {
            Group {
                if feed.openings.isEmpty {
                    ScrollView {
                        ContentUnavailableView(
                            "No openings yet",
                            systemImage: "briefcase",
                            description: Text("Pull to refresh. HiIntel checks the live feed daily and whenever you open the app.")
                        )
                        .padding(.top, 80)
                    }
                } else {
                    List(feed.openings) { opening in
                        row(for: opening)
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #endif
                }
            }
            .navigationTitle("HiIntel")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .refreshable { await refreshFromRemote() }
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hiintelFeedDidUpdate)) { _ in
            feed = FeedStore.load()
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
        _ = FeedStore.seedAppGroupIfNeeded()
        feed = FeedStore.load()
        Task { await refreshFromRemote() }
    }

    @MainActor
    private func refreshFromRemote() async {
        _ = await FeedStore.fetchRemote(
            timeout: FeedStore.hostFetchTimeout,
            reloadOnSuccess: true
        )
        feed = FeedStore.load()
        FeedStore.scheduleBackgroundRefresh()
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
