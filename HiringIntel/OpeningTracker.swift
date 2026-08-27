import Foundation
import Combine

@MainActor
final class OpeningTracker: ObservableObject {
    @Published private(set) var savedIDs: Set<String>
    @Published private(set) var appliedIDs: Set<String>

    init() {
        savedIDs = OpeningMarks.savedIDs()
        appliedIDs = OpeningMarks.appliedIDs()
    }

    func isSaved(_ id: String) -> Bool { savedIDs.contains(id) }
    func isApplied(_ id: String) -> Bool { appliedIDs.contains(id) }

    func toggleSaved(_ id: String) {
        if savedIDs.contains(id) {
            savedIDs.remove(id)
        } else {
            savedIDs.insert(id)
        }
        OpeningMarks.setSavedIDs(savedIDs)
        FeedStore.reloadTimelines()
    }

    func toggleApplied(_ id: String) {
        if appliedIDs.contains(id) {
            appliedIDs.remove(id)
        } else {
            appliedIDs.insert(id)
        }
        OpeningMarks.setAppliedIDs(appliedIDs)
    }

    func markApplied(_ id: String) {
        guard !appliedIDs.contains(id) else { return }
        appliedIDs.insert(id)
        OpeningMarks.setAppliedIDs(appliedIDs)
    }
}
