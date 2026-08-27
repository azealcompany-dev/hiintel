import Foundation

enum RoleFamily: String, CaseIterable, Identifiable {
    case sdr = "SDR"
    case bdr = "BDR"
    case ae = "AE"

    var id: String { rawValue }
}

enum WhereKind: String, CaseIterable, Identifiable {
    case us
    case remote
    case hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .us: return "US"
        case .remote: return "Remote"
        case .hybrid: return "Hybrid"
        }
    }

    static func classify(_ location: String) -> WhereKind? {
        let loc = location.lowercased()
        if loc.contains("hybrid") { return .hybrid }
        if loc.contains("remote") { return .remote }
        if isUS(location) { return .us }
        return nil
    }

    private static let stateAbbrev =
        "AL|AK|AZ|AR|CA|CO|CT|DC|DE|FL|GA|HI|IA|ID|IL|IN|KS|KY|LA|MA|MD|ME|MI|MN|MO|MS|MT|NC|ND|NE|NH|NJ|NM|NV|NY|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VA|VT|WA|WI|WV"

    private static let usNeedles = [
        "united states", "united states of america", "u.s.a.", "u.s.", "usa",
        "new york", "san francisco", "los angeles", "chicago", "austin", "seattle",
        "boston", "denver", "atlanta", "miami", "dallas", "houston", "oakland",
        "salt lake", "pittsburgh", "phoenix", "bay area", "california", "texas",
        "colorado", "illinois", "massachusetts", "florida", "washington, dc",
        "washington dc", "new york city",
    ]

    private static func isUS(_ location: String) -> Bool {
        let loc = location.lowercased()
        if usNeedles.contains(where: { loc.contains($0) }) { return true }
        if loc.range(of: "\\bus\\b", options: .regularExpression) != nil { return true }
        if location.range(
            of: ",\\s*(\(stateAbbrev))\\b",
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }
        if location.range(
            of: "\\b(\(stateAbbrev))\\b",
            options: [.regularExpression, .caseInsensitive]
        ) != nil,
           loc.contains("remote") == false {
            // Bare "IN"/"OR"/"ME" are too noisy unless a US city/state word is also present.
            let strong = ["ny", "ca", "tx", "wa", "il", "ma", "co", "ga", "dc", "pa", "az", "fl"]
            if strong.contains(where: { loc.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }) {
                return true
            }
        }
        return false
    }
}

enum WhenKind: String, CaseIterable, Identifiable {
    case new
    case today
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .new: return "New"
        case .today: return "Today"
        case .week: return "This week"
        }
    }

    func matches(_ opening: Opening, updated: Date?) -> Bool {
        guard let days = FeedDates.daysFromAnchor(posted: opening.postedDate, updated: updated) else {
            return false
        }
        switch self {
        case .today: return days <= 0
        case .new: return days <= 2
        case .week: return days <= 6
        }
    }
}

enum SortMode: String, CaseIterable, Identifiable {
    case newest
    case company

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest"
        case .company: return "By company"
        }
    }
}

enum ReaderViewMode: String, CaseIterable, Identifiable {
    case openings
    case saved
    case applied

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openings: return "Openings"
        case .saved: return "Saved"
        case .applied: return "Applied"
        }
    }
}

struct OpeningGroup: Identifiable {
    let id: String
    let title: String
    let openings: [Opening]
}

enum OpeningQuery {
    static func filtered(
        _ openings: [Opening],
        search: String,
        families: Set<String>,
        whereKind: WhereKind?,
        whenKind: WhenKind?,
        view: ReaderViewMode,
        updated: Date?,
        savedIDs: Set<String>,
        appliedIDs: Set<String>
    ) -> [Opening] {
        var items = openings
        switch view {
        case .openings:
            break
        case .saved:
            items = items.filter { savedIDs.contains($0.id) }
        case .applied:
            items = items.filter { appliedIDs.contains($0.id) }
        }

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items = items.filter { opening in
                opening.company.localizedCaseInsensitiveContains(query)
                    || opening.role.localizedCaseInsensitiveContains(query)
                    || opening.location.localizedCaseInsensitiveContains(query)
            }
        }

        if !families.isEmpty {
            items = items.filter { families.contains($0.roleFamily) }
        }
        if let whereKind {
            items = items.filter { WhereKind.classify($0.location) == whereKind }
        }
        if let whenKind {
            items = items.filter { whenKind.matches($0, updated: updated) }
        }
        return items
    }

    static func grouped(_ openings: [Opening], sort: SortMode) -> [OpeningGroup] {
        let sorted = openings.sorted(by: sortNewest)
        switch sort {
        case .company:
            let groups = Dictionary(grouping: sorted, by: \.company)
            return groups.keys
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .compactMap { name in
                    guard let rows = groups[name], !rows.isEmpty else { return nil }
                    return OpeningGroup(id: "company.\(name)", title: name, openings: rows)
                }
        case .newest:
            var today: [Opening] = []
            var week: [Opening] = []
            var earlier: [Opening] = []
            let cal = Calendar.current
            let now = Date()
            for opening in sorted {
                guard let posted = opening.postedDate else {
                    earlier.append(opening)
                    continue
                }
                if cal.isDateInToday(posted) {
                    today.append(opening)
                    continue
                }
                let days = cal.dateComponents(
                    [.day],
                    from: cal.startOfDay(for: posted),
                    to: cal.startOfDay(for: now)
                ).day ?? 99
                if days >= 0, days <= 6 {
                    week.append(opening)
                } else {
                    earlier.append(opening)
                }
            }
            return [
                today.isEmpty ? nil : OpeningGroup(id: "today", title: "Today", openings: today),
                week.isEmpty ? nil : OpeningGroup(id: "week", title: "This week", openings: week),
                earlier.isEmpty ? nil : OpeningGroup(id: "earlier", title: "Earlier", openings: earlier),
            ].compactMap { $0 }
        }
    }

    /// postedAt desc, then company, then role. YYYY-MM-dd strings sort chronologically.
    static func sortNewest(_ a: Opening, _ b: Opening) -> Bool {
        if a.postedAt != b.postedAt {
            return a.postedAt > b.postedAt
        }
        let company = a.company.localizedCaseInsensitiveCompare(b.company)
        if company != .orderedSame {
            return company == .orderedAscending
        }
        return a.role.localizedCaseInsensitiveCompare(b.role) == .orderedAscending
    }
}
