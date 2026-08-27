import Foundation

enum HiringOutreach {
    static func findManagerKeywords(for opening: Opening) -> String {
        if let name = opening.hiringManager?.name, !name.isEmpty {
            return "\(name) \(opening.company)"
        }
        let role = opening.hiringManager?.title.nilIfEmpty ?? opening.roleFamily
        return "\(opening.company) \(role) hiring manager"
    }

    static func messageKeywords(for opening: Opening) -> String {
        if let name = opening.hiringManager?.name, !name.isEmpty {
            return "\(name) \(opening.company)"
        }
        if let title = opening.hiringManager?.title.nilIfEmpty {
            return "\(opening.company) \(title)"
        }
        let family = opening.roleFamily.isEmpty ? "sales" : opening.roleFamily
        return "\(opening.company) \(family) manager"
    }

    static func referralKeywords(for opening: Opening) -> String {
        let family: String
        switch opening.roleFamily {
        case "AE": family = "Account Executive"
        case "BDR": family = "BDR"
        case "SDR": family = "SDR"
        default:
            family = opening.roleFamily.isEmpty ? "Account Executive" : opening.roleFamily
        }
        return "\(opening.company) \(family)"
    }

    static func proof(for opening: Opening) -> String {
        let family = opening.roleFamily.isEmpty ? "sales" : opening.roleFamily
        return "quota-carrying \(family)"
    }

    static func referralAsk(for opening: Opening) -> String {
        let family: String
        switch opening.roleFamily {
        case "AE": family = "Account Executive"
        case "BDR": family = "BDR"
        case "SDR": family = "SDR"
        default: family = opening.roleFamily.isEmpty ? "sales" : opening.roleFamily
        }
        return "Anyone at \(opening.company) who could refer me for the \(opening.role) (\(family)) opening?"
    }

    static func note(for opening: Opening) -> String {
        let place = opening.location.isEmpty ? opening.shortLocation : opening.location
        let applied: String
        if place.isEmpty {
            applied = "Applied to \(opening.role)."
        } else {
            applied = "Applied to \(opening.role) in \(place)."
        }
        let family = opening.roleFamily.isEmpty ? "sales" : opening.roleFamily
        let body = "\(applied) Been doing \(family) outbound / quota-carrying work. Worth 15 minutes?"
        if let first = opening.hiringManager?.firstName {
            return "Hi \(first) — \(body)"
        }
        return body
    }

    static func linkedInPeopleSearch(_ keywords: String) -> URL? {
        searchURL("https://www.linkedin.com/search/results/people/", queryName: "keywords", value: keywords)
    }

    static func salesNavigatorSearch(_ keywords: String) -> URL? {
        searchURL("https://www.linkedin.com/sales/search/people", queryName: "keywords", value: keywords)
    }

    static func theOrgSearch(_ company: String) -> URL? {
        searchURL("https://theorg.com/search", queryName: "q", value: company)
    }

    static func findManagerURL(for opening: Opening) -> URL? {
        linkedInPeopleSearch(findManagerKeywords(for: opening))
    }

    static func messageURL(for opening: Opening) -> URL? {
        linkedInPeopleSearch(messageKeywords(for: opening))
    }

    static func referralURL(for opening: Opening) -> URL? {
        linkedInPeopleSearch(referralKeywords(for: opening))
    }

    private static func searchURL(_ base: String, queryName: String, value: String) -> URL? {
        var comps = URLComponents(string: base)
        comps?.queryItems = [URLQueryItem(name: queryName, value: value)]
        return comps?.url
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
