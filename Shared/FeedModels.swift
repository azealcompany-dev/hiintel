import Foundation

struct HiringManager: Codable, Hashable, Sendable {
    let name: String?
    let title: String
    let source: String

    var displayLine: String? {
        let trimmedName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty, trimmedTitle.isEmpty { return nil }
        if trimmedName.isEmpty { return trimmedTitle }
        if trimmedTitle.isEmpty { return trimmedName }
        return "\(trimmedName) · \(trimmedTitle)"
    }

    var firstName: String? {
        guard let name, let first = name.split(whereSeparator: { $0.isWhitespace }).first else {
            return nil
        }
        let value = String(first)
        return value.isEmpty ? nil : value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawName = try c.decodeIfPresent(String.self, forKey: .name)
        name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        title = (try c.decodeIfPresent(String.self, forKey: .title) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        source = (try c.decodeIfPresent(String.self, forKey: .source) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct Compensation: Codable, Hashable, Sendable {
    let text: String
    let min: Double?
    let max: Double?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case text, min, max, currency
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = (try c.decodeIfPresent(String.self, forKey: .text) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        min = Self.number(c, .min)
        max = Self.number(c, .max)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
    }

    private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? c.decode(Double.self, forKey: key) { return value }
        if let value = try? c.decode(Int.self, forKey: key) { return Double(value) }
        return nil
    }
}

struct Opening: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let company: String
    let role: String
    let roleFamily: String
    let location: String
    let url: String
    let lookingFor: String
    let companyBrief: String
    let postedAt: String
    let hiringManager: HiringManager?
    let compensation: Compensation?
    let segment: String?
    let workplace: String?
    let quotaCarrying: Bool?
    let oteText: String?
    let travelText: String?
    let reposted: Bool?
    var isClosed: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, company, role, roleFamily, location, url, lookingFor, companyBrief, postedAt
        case hiringManager
        case compensation = "comp"
        case segment, workplace, quotaCarrying, oteText, travelText, reposted
    }

    var jobURL: URL? { URL(string: url) }

    var lookingForPlain: String { HTMLText.plain(lookingFor) }
    var companyBriefPlain: String { HTMLText.plain(companyBrief) }
    var postedDate: Date? { FeedDates.parsePosted(postedAt) }

    var companyInitials: String {
        let words = company.split { $0.isWhitespace || $0 == "-" }.filter { !$0.isEmpty }
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        let alnum = company.filter { $0.isLetter || $0.isNumber }
        let letters = alnum.isEmpty ? company : String(alnum)
        return String(letters.prefix(2)).uppercased()
    }

    var shortLocation: String {
        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !loc.isEmpty else { return "" }
        let lower = loc.lowercased()
        if lower == "remote" || lower.hasPrefix("remote,") || lower.hasPrefix("remote ")
            || lower.hasPrefix("remote-") || lower.hasPrefix("remote/") {
            return "Remote"
        }
        if lower == "hybrid" { return "Hybrid" }
        if lower == "united states - remote" || lower.hasPrefix("us remote") { return "Remote" }
        let first = loc.split { $0 == "," || $0 == "•" || $0 == ";" }
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? loc
        let firstLower = first.lowercased()
        if firstLower == "remote" || firstLower.contains("remote") && first.count <= 24 {
            return "Remote"
        }
        return first
    }

    func isNew(relativeTo updated: Date?) -> Bool {
        FeedDates.isNew(posted: postedDate, updated: updated)
    }

    init(
        id: String,
        company: String,
        role: String,
        roleFamily: String = "",
        location: String = "",
        url: String = "",
        lookingFor: String = "",
        companyBrief: String = "",
        postedAt: String = "",
        hiringManager: HiringManager? = nil,
        compensation: Compensation? = nil,
        segment: String? = nil,
        workplace: String? = nil,
        quotaCarrying: Bool? = nil,
        oteText: String? = nil,
        travelText: String? = nil,
        reposted: Bool? = nil,
        isClosed: Bool = false
    ) {
        self.id = id
        self.company = company
        self.role = role
        self.roleFamily = roleFamily
        self.location = location
        self.url = url
        self.lookingFor = lookingFor
        self.companyBrief = companyBrief
        self.postedAt = postedAt
        self.hiringManager = hiringManager
        self.compensation = compensation
        self.segment = segment
        self.workplace = workplace
        self.quotaCarrying = quotaCarrying
        self.oteText = oteText
        self.travelText = travelText
        self.reposted = reposted
        self.isClosed = isClosed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        company = try c.decode(String.self, forKey: .company)
        role = try c.decode(String.self, forKey: .role)
        roleFamily = try c.decodeIfPresent(String.self, forKey: .roleFamily) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        lookingFor = try c.decodeIfPresent(String.self, forKey: .lookingFor) ?? ""
        companyBrief = try c.decodeIfPresent(String.self, forKey: .companyBrief) ?? ""
        postedAt = try c.decodeIfPresent(String.self, forKey: .postedAt) ?? ""
        hiringManager = try c.decodeIfPresent(HiringManager.self, forKey: .hiringManager)
        compensation = try c.decodeIfPresent(Compensation.self, forKey: .compensation)
        segment = try c.decodeIfPresent(String.self, forKey: .segment)?.nilIfEmpty
        workplace = try c.decodeIfPresent(String.self, forKey: .workplace)?.nilIfEmpty
        quotaCarrying = try c.decodeIfPresent(Bool.self, forKey: .quotaCarrying)
        oteText = try c.decodeIfPresent(String.self, forKey: .oteText)?.nilIfEmpty
        travelText = try c.decodeIfPresent(String.self, forKey: .travelText)?.nilIfEmpty
        reposted = try c.decodeIfPresent(Bool.self, forKey: .reposted)
        isClosed = false
    }

    func closedCopy() -> Opening {
        var copy = self
        copy.isClosed = true
        return copy
    }
}

struct OpeningsFeed: Codable, Hashable, Sendable {
    let updatedAt: String?
    let openings: [Opening]
    let companyCounts: [String: [String: Int]]?

    static let empty = OpeningsFeed(updatedAt: nil, openings: [], companyCounts: nil)

    var updatedDate: Date? { FeedDates.parseUpdated(updatedAt) }

    var isStale: Bool {
        guard let updated = updatedDate else { return false }
        return Date().timeIntervalSince(updated) > 36 * 60 * 60
    }

    init(updatedAt: String?, openings: [Opening], companyCounts: [String: [String: Int]]? = nil) {
        self.updatedAt = updatedAt
        self.openings = openings
        self.companyCounts = companyCounts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        openings = try c.decodeIfPresent([Opening].self, forKey: .openings) ?? []
        companyCounts = try c.decodeIfPresent([String: [String: Int]].self, forKey: .companyCounts)
    }

    func aeThisWeek(for company: String) -> Int {
        let cal = Calendar.current
        let now = Date()
        return openings.filter { opening in
            guard opening.company == company, opening.roleFamily == "AE", let posted = opening.postedDate else {
                return false
            }
            let days = cal.dateComponents(
                [.day],
                from: cal.startOfDay(for: posted),
                to: cal.startOfDay(for: now)
            ).day ?? 99
            return days >= 0 && days <= 6
        }.count
    }
}
