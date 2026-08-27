import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum FeedSourceLabel: String {
    case live
    case cache
    case bundled
}

private struct UndoToast: Equatable {
    enum Kind { case saved, unsaved, applied, unapplied }
    let kind: Kind
    let opening: Opening
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tracker = OpeningTracker()
    @State private var feed: OpeningsFeed = .empty
    @State private var feedSource: FeedSourceLabel = .bundled
    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var selectedID: String?
    @State private var newSinceLast = 0
    @State private var showNewBanner = false
    @State private var undo: UndoToast?
    @State private var showOnboarding = false

    @AppStorage("hiintel.reader.families") private var familiesRaw = ""
    @AppStorage("hiintel.reader.where") private var whereRaw = ""
    @AppStorage("hiintel.reader.when") private var whenRaw = ""
    @AppStorage("hiintel.reader.sort") private var sortRaw = SortMode.newest.rawValue
    @AppStorage("hiintel.reader.view") private var viewRaw = ReaderViewMode.openings.rawValue
    @AppStorage("hiintel.reader.segment") private var segmentRaw = ""
    @AppStorage("hiintel.reader.workplace") private var workplaceRaw = ""
    @AppStorage("hiintel.reader.metro") private var metroRaw = ""
    @AppStorage("hiintel.onboarding.done") private var onboardingDone = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 520)
        } detail: {
            detail
        }
        .onAppear(perform: bootstrap)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refresh()
                recountNew()
            } else if phase == .background {
                OpeningMarks.lastAppOpen = Date()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hiintelFeedDidUpdate)) { _ in
            feed = FeedStore.load()
            tracker.cancelClosedNotifications(liveIDs: Set(feed.openings.map(\.id)))
            AppBadge.refresh(from: feed)
        }
        .onReceive(NotificationCenter.default.publisher(for: .hiintelOpenJob)) { note in
            if let id = note.object as? String {
                selectedID = id
                viewRaw = ReaderViewMode.openings.rawValue
            }
        }
        .onOpenURL { url in
            handleOpenURL(url)
        }
        .task(id: searchText) {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                debouncedSearch = ""
                return
            }
            try? await Task.sleep(nanoseconds: 280_000_000)
            debouncedSearch = searchText
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(
                companies: feed.openings.map(\.company).uniqued(),
                familiesRaw: $familiesRaw
            ) { names in
                tracker.pinCompanies(names)
            } onDone: {
                onboardingDone = true
                showOnboarding = false
            }
        }
        .overlay(alignment: .bottom) {
            if let undo {
                undoBanner(undo)
                    .padding(.bottom, 24)
            }
        }
    }

    private var sidebar: some View {
        Group {
            if feed.openings.isEmpty && viewMode == .openings {
                ScrollView {
                    ContentUnavailableView(
                        "No openings yet",
                        systemImage: "briefcase",
                        description: Text("Pull to refresh. HiIntel checks the live feed daily and whenever you open the app.")
                    )
                    .padding(.top, 80)
                }
            } else if groups.isEmpty {
                emptyFiltered
            } else {
                List(selection: $selectedID) {
                    ForEach(groups) { group in
                        Section(header: Text(sectionTitle(group))) {
                            ForEach(group.openings) { opening in
                                NavigationLink(value: opening.id) {
                                    OpeningRowView(
                                        opening: opening,
                                        isNew: opening.isNew(relativeTo: feed.updatedDate),
                                        isSaved: tracker.isSaved(opening.id),
                                        isApplied: tracker.isApplied(opening.id),
                                        isPinned: tracker.isPinned(opening.company)
                                    )
                                }
                                .tag(opening.id)
                                .contextMenu { rowContextMenu(opening) }
                                #if os(iOS)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        applyUndo(.saved, opening) { _ = tracker.toggleSaved(opening) }
                                    } label: {
                                        Label("Save", systemImage: "bookmark")
                                    }
                                    .tint(.accentColor)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        applyUndo(.applied, opening) { _ = tracker.toggleApplied(opening) }
                                    } label: {
                                        Label("Applied", systemImage: "checkmark.circle")
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
                .onAppear {
                    AppBadge.clear()
                }
            }
        }
        .navigationTitle("HiIntel")
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
            VStack(spacing: 0) {
                if showNewBanner, newSinceLast > 0, viewMode == .openings {
                    Button {
                        showNewBanner = false
                        AppBadge.clear()
                    } label: {
                        Text(newSinceLast == 1 ? "1 new since you last opened" : "\(newSinceLast) new since you last opened")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                if !feed.openings.isEmpty || viewMode != .openings {
                    FilterBarView(
                    feed: feed,
                    familyCounts: familyCounts,
                    sourceLabel: feedSource.rawValue,
                    isStale: feed.isStale,
                    familiesRaw: $familiesRaw,
                    whereRaw: $whereRaw,
                    whenRaw: $whenRaw,
                    sortRaw: $sortRaw,
                    viewRaw: $viewRaw,
                    segmentRaw: $segmentRaw,
                    workplaceRaw: $workplaceRaw,
                    metroRaw: $metroRaw,
                    hasActiveFilters: hasNarrowingFilters,
                    onClear: clearFilters
                )
                }
            }
        }
        .refreshable { await refreshFromRemote() }
    }

    @ViewBuilder
    private var detail: some View {
        if let opening = selectedOpening {
            OpeningDetailView(
                opening: opening,
                feed: feed,
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
        return tracker.resolved(selectedID, live: feed.openings)
    }

    private var selectedFamilies: Set<String> {
        Set(familiesRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private var whereKind: WhereKind? { WhereKind(rawValue: whereRaw) }
    private var whenKind: WhenKind? { WhenKind(rawValue: whenRaw) }
    private var sortMode: SortMode { SortMode(rawValue: sortRaw) ?? .newest }
    private var viewMode: ReaderViewMode { ReaderViewMode(rawValue: viewRaw) ?? .openings }
    private var segmentKind: SegmentKind? { SegmentKind(rawValue: segmentRaw) }
    private var workplaceKind: WorkplaceKind? { WorkplaceKind(rawValue: workplaceRaw) }
    private var metroKind: MetroKind? { MetroKind(rawValue: metroRaw) }

    private var hasNarrowingFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedFamilies.isEmpty
            || whereKind != nil
            || whenKind != nil
            || segmentKind != nil
            || workplaceKind != nil
            || metroKind != nil
    }

    private var baseOpenings: [Opening] {
        tracker.openingsForView(viewMode, live: feed.openings)
    }

    private var filteredOpenings: [Opening] {
        OpeningQuery.filtered(
            baseOpenings,
            search: debouncedSearch,
            families: selectedFamilies,
            whereKind: whereKind,
            whenKind: whenKind,
            segment: segmentKind,
            workplace: workplaceKind,
            metro: metroKind,
            view: viewMode,
            updated: feed.updatedDate,
            mutedCompanies: tracker.mutedCompanies
        )
    }

    private var groups: [OpeningGroup] {
        OpeningQuery.grouped(filteredOpenings, sort: sortMode, pinned: tracker.pinnedCompanies)
    }

    private var familyCounts: [String: Int] {
        var counts: [String: Int] = ["SDR": 0, "BDR": 0, "AE": 0]
        for opening in feed.openings {
            counts[opening.roleFamily, default: 0] += 1
        }
        return counts
    }

    private func sectionTitle(_ group: OpeningGroup) -> String {
        if sortMode == .company {
            let week = feed.aeThisWeek(for: group.title)
            if week > 0 {
                return "\(group.title) · \(week) AE this week"
            }
        }
        return group.title
    }

    @ViewBuilder
    private func rowContextMenu(_ opening: Opening) -> some View {
        Button {
            applyUndo(.saved, opening) { _ = tracker.toggleSaved(opening) }
        } label: {
            Label(
                tracker.isSaved(opening.id) ? "Remove from saved" : "Save",
                systemImage: tracker.isSaved(opening.id) ? "bookmark.slash" : "bookmark"
            )
        }
        Button {
            applyUndo(.applied, opening) { _ = tracker.toggleApplied(opening) }
        } label: {
            Label(
                tracker.isApplied(opening.id) ? "Mark not applied" : "Applied",
                systemImage: "checkmark.circle"
            )
        }
        Button {
            tracker.togglePinned(opening.company)
        } label: {
            Label(
                tracker.isPinned(opening.company) ? "Unpin company" : "Pin company",
                systemImage: "pin"
            )
        }
        Button {
            tracker.toggleMuted(opening.company)
        } label: {
            Label(
                tracker.isMuted(opening.company) ? "Unmute company" : "Mute company",
                systemImage: "bell.slash"
            )
        }
        Button {
            copyLink(opening)
        } label: {
            Label("Copy link", systemImage: "link")
        }
        if let url = opening.jobURL {
            ShareLink(item: url, message: Text("\(opening.role) at \(opening.company)")) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func undoBanner(_ toast: UndoToast) -> some View {
        HStack {
            Text(undoLabel(toast))
            Spacer()
            Button("Undo") {
                switch toast.kind {
                case .saved, .unsaved:
                    _ = tracker.toggleSaved(toast.opening)
                case .applied, .unapplied:
                    _ = tracker.toggleApplied(toast.opening)
                }
                undo = nil
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func undoLabel(_ toast: UndoToast) -> String {
        switch toast.kind {
        case .saved: return "Saved"
        case .unsaved: return "Removed from saved"
        case .applied: return "Marked applied"
        case .unapplied: return "Unmarked applied"
        }
    }

    private func applyUndo(_ kind: UndoToast.Kind, _ opening: Opening, _ action: () -> Void) {
        let wasSaved = tracker.isSaved(opening.id)
        let wasApplied = tracker.isApplied(opening.id)
        action()
        let resolved: UndoToast.Kind
        switch kind {
        case .saved, .unsaved:
            resolved = tracker.isSaved(opening.id) && !wasSaved ? .saved : .unsaved
        case .applied, .unapplied:
            resolved = tracker.isApplied(opening.id) && !wasApplied ? .applied : .unapplied
        }
        undo = UndoToast(kind: resolved, opening: opening)
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if undo?.opening.id == opening.id { undo = nil }
        }
    }

    private func copyLink(_ opening: Opening) {
        guard !opening.url.isEmpty else { return }
        #if os(iOS)
        UIPasteboard.general.string = opening.url
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(opening.url, forType: .string)
        #endif
    }

    private func clearFilters() {
        searchText = ""
        debouncedSearch = ""
        familiesRaw = ""
        whereRaw = ""
        whenRaw = ""
        segmentRaw = ""
        workplaceRaw = ""
        metroRaw = ""
    }

    private func bootstrap() {
        refresh()
        recountNew()
        if !onboardingDone {
            showOnboarding = true
        }
        ReferralNudge.requestAccess()
    }

    private func recountNew() {
        newSinceLast = OpeningMarks.newCount(in: feed, since: OpeningMarks.lastAppOpen)
        showNewBanner = newSinceLast > 0
        AppBadge.refresh(from: feed)
    }

    private func handleOpenURL(_ url: URL) {
        if url.scheme == "hiringintel" {
            let id = url.pathComponents.last(where: { $0 != "/" }) ?? ""
            if !id.isEmpty {
                selectedID = id
            }
            return
        }
        JobOpener.open(url)
    }

    private func refresh() {
        _ = FeedStore.seedAppGroupIfNeeded()
        feed = FeedStore.load()
        feedSource = FeedStore.lastRemoteFetchDate == nil ? .bundled : .cache
        tracker.cancelClosedNotifications(liveIDs: Set(feed.openings.map(\.id)))
        Task { await refreshFromRemote() }
    }

    @MainActor
    private func refreshFromRemote() async {
        if let remote = await FeedStore.fetchRemote(
            timeout: FeedStore.hostFetchTimeout,
            reloadOnSuccess: true
        ) {
            feed = remote.openings.isEmpty ? FeedStore.load() : remote
            feedSource = remote.openings.isEmpty ? .cache : .live
        } else {
            feed = FeedStore.load()
            feedSource = FeedStore.lastRemoteFetchDate == nil ? .bundled : .cache
        }
        FeedStore.scheduleBackgroundRefresh()
        tracker.cancelClosedNotifications(liveIDs: Set(feed.openings.map(\.id)))
        AppBadge.refresh(from: feed)
        recountNew()
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in self where seen.insert(item).inserted {
            out.append(item)
        }
        return out.sorted()
    }
}
