import Foundation

enum FeedDates {
    static func parsePosted(_ raw: String) -> Date? {
        let ymd = String(raw.prefix(10))
        let parts = ymd.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              year > 2000,
              (1...12).contains(month),
              (1...31).contains(day)
        else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func parseUpdated(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        return parsePosted(raw)
    }

    /// Inclusive: posted on the updated day, the day before, or two days before.
    static func isNew(posted: Date?, updated: Date?) -> Bool {
        guard let posted else { return false }
        let anchor = updated ?? Date()
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: posted),
            to: cal.startOfDay(for: anchor)
        ).day ?? 99
        return days <= 2
    }

    static func daysFromAnchor(posted: Date?, updated: Date?) -> Int? {
        guard let posted else { return nil }
        let anchor = updated ?? Date()
        let cal = Calendar.current
        return cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: posted),
            to: cal.startOfDay(for: anchor)
        ).day
    }

    static func relativePosted(_ raw: String) -> String {
        guard let posted = parsePosted(raw) else {
            return raw.isEmpty ? "" : raw
        }
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: posted),
            to: cal.startOfDay(for: Date())
        ).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 14 { return "\(days)d ago" }
        if days < 60 { return "\(max(days / 7, 1))w ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: posted)
    }

    static func updatedLabel(_ raw: String?) -> String {
        guard let date = parseUpdated(raw) else { return "Updated —" }
        if date > Date() { return "Updated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}
