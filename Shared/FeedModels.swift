import Foundation

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
        postedAt: String = ""
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
    }
}

struct OpeningsFeed: Codable, Hashable, Sendable {
    let updatedAt: String?
    let openings: [Opening]

    static let empty = OpeningsFeed(updatedAt: nil, openings: [])

    var updatedDate: Date? { FeedDates.parseUpdated(updatedAt) }

    init(updatedAt: String?, openings: [Opening]) {
        self.updatedAt = updatedAt
        self.openings = openings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        openings = try c.decodeIfPresent([Opening].self, forKey: .openings) ?? []
    }
}
