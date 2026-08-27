import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tracker = OpeningTracker()
    @State private var feed: OpeningsFeed = .empty
    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var selectedID: String?

    @AppStorage("hiintel.reader.families") private var familiesRaw = ""
    @AppStorage("hiintel.reader.where") private var whereRaw = ""
    @AppStorage("hiintel.reader.when") private var whenRaw = ""
    @AppStorage("hiintel.reader.sort") private var sortRaw = SortMode.newest.rawValue
    @AppStorage("hiintel.reader.view") private var viewRaw = ReaderViewMode.openings.rawValue

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 520)
        } detail: {
            detail
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
        .task(id: searchText) {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                debouncedSearch = ""
                return
            }
            try? await Task.sleep(nanoseconds: 280_000_000)
            debouncedSearch = searchText
        }
    }

    private var sidebar: some View {
        Group {
            if feed.openings.isEmpty {
                ScrollView {
                    ContentUnavailableView(
                        "No openings yet",
                        systemImage: "briefcase",
                        description: Text("Pull to refresh. Hiintel checks the live feed daily and whenever you open the app.")
                    )
                    .padding(.top, 80)
                }
            } else if groups.isEmpty {
                emptyFiltered
            } else {
                List(selection: $selectedID) {
                    ForEach(groups) { group in
                        Section(group.title) {
                            ForEach(group.openings) { opening in
                                NavigationLink(value: opening.id) {
                                    OpeningRowView(
                                        opening: opening,
                                        isNew: opening.isNew(relativeTo: feed.updatedDate),
                                        isSaved: tracker.isSaved(opening.id),
                                        isApplied: tracker.isApplied(opening.id)
                                    )
                                }
                                .tag(opening.id)
                                .contextMenu { rowContextMenu(opening) }
                                #if os(iOS)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        tracker.toggleSaved(opening.id)
                                    } label: {
                                        Label(
                                            tracker.isSaved(opening.id) ? "Unsave" : "Save",
                                            systemImage: "bookmark"
                                        )
                                    }
                                    .tint(.accentColor)
                                    Button {
                                        tracker.toggleApplied(opening.id)
                                    } label: {
                                        Label(
                                            tracker.isApplied(opening.id) ? "Not applied" : "Applied",
                                            systemImage: "checkmark.circle"
                                        )
                                    }
                                    .tint(.green)
                                }
                                #endif
                            }
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #elseif os(macOS)
                .listStyle(.sidebar)
                #endif
            }
        }
        .navigationTitle("Hiintel")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Company, role, or location"
        )
        #else
        .searchable(text: $searchText, prompt: "Company, role, or location")
        #endif
        .safeAreaInset(edge: .top, spacing: 0) {
            if !feed.openings.isEmpty {
                FilterBarView(
                    feed: feed,
                    familyCounts: familyCounts,
                    familiesRaw: $familiesRaw,
                    whereRaw: $whereRaw,
                    whenRaw: $whenRaw,
                    sortRaw: $sortRaw,
                    viewRaw: $viewRaw,
                    hasActiveFilters: hasNarrowingFilters,
                    onClear: clearFilters
                )
            }
        }
        .refreshable { await refreshFromRemote() }
    }

    @ViewBuilder
    private var detail: some View {
        if let opening = selectedOpening {
            OpeningDetailView(
                opening: opening,
                feedUpdated: feed.updatedDate,
                tracker: tracker
            )
        } else {
            ContentUnavailableView(
                "Select an opening",
                systemImage: "briefcase",
                description: Text("Pick a role to read the brief, save it, or copy the link.")
            )
        }
    }

    private var emptyFiltered: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptyImage,
                    description: Text(emptyDescription)
                )
                if hasNarrowingFilters {
                    Button("Clear filters", action: clearFilters)
                        .buttonStyle(.bordered)
                }
            }
            .padding(.top, 80)
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyTitle: String {
        if hasNarrowingFilters { return "No openings match" }
        switch viewMode {
        case .saved: return "No saved openings"
        case .applied: return "No applied openings"
        case .openings: return "No openings match"
        }
    }

    private var emptyImage: String {
        switch viewMode {
        case .saved: return "bookmark"
        case .applied: return "checkmark.circle"
        case .openings: return "line.3.horizontal.decrease.circle"
        }
    }

    private var emptyDescription: String {
        if hasNarrowingFilters {
            return "Try a different search or clear the chips."
        }
        switch viewMode {
        case .saved: return "Bookmark a role to keep it here."
        case .applied: return "Mark a role applied after you open the posting."
        case .openings: return "Try a different search or clear the chips."
        }
    }

    private var selectedOpening: Opening? {
        guard let selectedID else { return nil }
        return feed.openings.first(where: { $0.id == selectedID })
    }

    private var selectedFamilies: Set<String> {
        Set(familiesRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private var whereKind: WhereKind? { WhereKind(rawValue: whereRaw) }
    private var whenKind: WhenKind? { WhenKind(rawValue: whenRaw) }
    private var sortMode: SortMode { SortMode(rawValue: sortRaw) ?? .newest }
    private var viewMode: ReaderViewMode { ReaderViewMode(rawValue: viewRaw) ?? .openings }

    private var hasNarrowingFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedFamilies.isEmpty
            || whereKind != nil
            || whenKind != nil
    }

    private var filteredOpenings: [Opening] {
        OpeningQuery.filtered(
            feed.openings,
            search: debouncedSearch,
            families: selectedFamilies,
            whereKind: whereKind,
            whenKind: whenKind,
            view: viewMode,
            updated: feed.updatedDate,
            savedIDs: tracker.savedIDs,
            appliedIDs: tracker.appliedIDs
        )
    }

    private var groups: [OpeningGroup] {
        OpeningQuery.grouped(filteredOpenings, sort: sortMode)
    }

    private var familyCounts: [String: Int] {
        var counts: [String: Int] = ["SDR": 0, "BDR": 0, "AE": 0]
        for opening in feed.openings {
            counts[opening.roleFamily, default: 0] += 1
        }
        return counts
    }

    @ViewBuilder
    private func rowContextMenu(_ opening: Opening) -> some View {
        Button {
            tracker.toggleSaved(opening.id)
        } label: {
            Label(
                tracker.isSaved(opening.id) ? "Remove from saved" : "Save",
                systemImage: tracker.isSaved(opening.id) ? "bookmark.slash" : "bookmark"
            )
        }
        Button {
            tracker.toggleApplied(opening.id)
        } label: {
            Label(
                tracker.isApplied(opening.id) ? "Mark not applied" : "Mark applied",
                systemImage: "checkmark.circle"
            )
        }
        if let url = opening.jobURL {
            Button {
                JobOpener.open(url)
            } label: {
                Label("Open posting", systemImage: "arrow.up.right")
            }
        }
    }

    private func clearFilters() {
        searchText = ""
        debouncedSearch = ""
        familiesRaw = ""
        whereRaw = ""
        whenRaw = ""
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
