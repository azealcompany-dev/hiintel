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
