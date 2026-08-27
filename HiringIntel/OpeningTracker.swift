import Foundation
import Combine

@MainActor
final class OpeningTracker: ObservableObject {
    @Published private(set) var savedIDs: Set<String>
    @Published private(set) var appliedIDs: Set<String>
    @Published private(set) var pinnedCompanies: Set<String>
    @Published private(set) var mutedCompanies: Set<String>
    @Published private(set) var followUpDoneIDs: Set<String>
    @Published private(set) var notes: [String: String]
    @Published private(set) var dates: [String: String]
    @Published private(set) var snapshots: [String: Opening]

    init() {
        savedIDs = OpeningMarks.savedIDs()
        appliedIDs = OpeningMarks.appliedIDs()
        pinnedCompanies = OpeningMarks.pinnedCompanies()
        mutedCompanies = OpeningMarks.mutedCompanies()
        followUpDoneIDs = OpeningMarks.followUpDoneIDs()
        notes = OpeningMarks.notes()
        dates = OpeningMarks.dates()
        snapshots = OpeningMarks.snapshots()
    }

    func isSaved(_ id: String) -> Bool { savedIDs.contains(id) }
    func isApplied(_ id: String) -> Bool { appliedIDs.contains(id) }
    func isPinned(_ company: String) -> Bool { pinnedCompanies.contains(company) }
    func isMuted(_ company: String) -> Bool { mutedCompanies.contains(company) }
    func isFollowUpDone(_ id: String) -> Bool { followUpDoneIDs.contains(id) }
    func note(for id: String) -> String { notes[id] ?? "" }
    func date(for id: String) -> String? { dates[id] }

    @discardableResult
    func toggleSaved(_ opening: Opening) -> Bool {
        let on = !savedIDs.contains(opening.id)
        if on {
            savedIDs.insert(opening.id)
            remember(opening)
        } else {
            savedIDs.remove(opening.id)
            ReferralNudge.cancel(id: opening.id)
        }
        OpeningMarks.setSavedIDs(savedIDs)
        FeedStore.reloadTimelines()
        return on
    }

    @discardableResult
    func toggleApplied(_ opening: Opening) -> Bool {
        let on = !appliedIDs.contains(opening.id)
        if on {
            appliedIDs.insert(opening.id)
            remember(opening)
            ReferralNudge.schedule(opening: opening)
        } else {
            appliedIDs.remove(opening.id)
            ReferralNudge.cancel(id: opening.id)
        }
        OpeningMarks.setAppliedIDs(appliedIDs)
        return on
    }

    func markApplied(_ opening: Opening) {
        guard !appliedIDs.contains(opening.id) else { return }
        _ = toggleApplied(opening)
    }

    func togglePinned(_ company: String) {
        if pinnedCompanies.contains(company) {
            pinnedCompanies.remove(company)
        } else {
            pinnedCompanies.insert(company)
            mutedCompanies.remove(company)
            OpeningMarks.setMutedCompanies(mutedCompanies)
        }
        OpeningMarks.setPinnedCompanies(pinnedCompanies)
        FeedStore.reloadTimelines()
    }

    func toggleMuted(_ company: String) {
        if mutedCompanies.contains(company) {
            mutedCompanies.remove(company)
        } else {
            mutedCompanies.insert(company)
            pinnedCompanies.remove(company)
            OpeningMarks.setPinnedCompanies(pinnedCompanies)
        }
        OpeningMarks.setMutedCompanies(mutedCompanies)
        FeedStore.reloadTimelines()
    }

    func setNote(_ note: String, for id: String) {
        OpeningMarks.setNote(note, for: id)
        notes = OpeningMarks.notes()
    }

    func setDate(_ iso: String?, for id: String) {
        OpeningMarks.setDate(iso, for: id)
        dates = OpeningMarks.dates()
    }

    func markFollowUpDone(_ id: String, done: Bool) {
        if done {
            followUpDoneIDs.insert(id)
            ReferralNudge.cancel(id: id)
        } else {
            followUpDoneIDs.remove(id)
        }
        OpeningMarks.setFollowUpDoneIDs(followUpDoneIDs)
    }

    func pinCompanies<S: Sequence>(_ names: S) where S.Element == String {
        pinnedCompanies.formUnion(names)
        OpeningMarks.setPinnedCompanies(pinnedCompanies)
        FeedStore.reloadTimelines()
    }

    func resolved(_ id: String, live: [Opening]) -> Opening? {
        if let live = live.first(where: { $0.id == id }) {
            return live
        }
        guard let snap = snapshots[id] else { return nil }
        return snap.closedCopy()
    }

    func openingsForView(_ view: ReaderViewMode, live: [Opening]) -> [Opening] {
        let liveByID = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        let ids: Set<String>
        switch view {
        case .openings:
            return live
        case .saved:
            ids = savedIDs
        case .applied:
            ids = appliedIDs
        }
        return ids.compactMap { id in
            if let opening = liveByID[id] { return opening }
            return snapshots[id]?.closedCopy()
        }
    }

    func cancelClosedNotifications(liveIDs: Set<String>) {
        let tracked = savedIDs.union(appliedIDs)
        for id in tracked where !liveIDs.contains(id) {
            ReferralNudge.cancel(id: id)
        }
    }

    private func remember(_ opening: Opening) {
        OpeningMarks.saveSnapshot(opening)
        snapshots = OpeningMarks.snapshots()
    }
}
