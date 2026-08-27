import SwiftUI

struct OpeningRowView: View {
    let opening: Opening
    let isNew: Bool
    let isSaved: Bool
    let isApplied: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            initials
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(opening.role)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    if isNew {
                        Text("New")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !opening.roleFamily.isEmpty {
                        familyPill
                    }
                    if let relative = relativeDate, !relative.isEmpty {
                        Text(relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    if isSaved {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Saved")
                    }
                    if isApplied {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .accessibilityLabel("Applied")
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        let location = opening.shortLocation
        if location.isEmpty { return opening.company }
        return "\(opening.company) · \(location)"
    }

    private var relativeDate: String? {
        let value = FeedDates.relativePosted(opening.postedAt)
        return value.isEmpty ? nil : value
    }

    private var initials: some View {
        Text(opening.companyInitials)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(avatarColor, in: Circle())
            .accessibilityHidden(true)
    }

    private var familyPill: some View {
        Text(opening.roleFamily)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(familyColor.opacity(0.16), in: Capsule())
            .foregroundStyle(familyColor)
    }

    private var familyColor: Color {
        switch opening.roleFamily {
        case "SDR": return .blue
        case "BDR": return .purple
        case "AE": return .orange
        default: return .secondary
        }
    }

    private var avatarColor: Color {
        let palette: [Color] = [.blue, .indigo, .teal, .orange, .pink, .purple, .cyan, .mint]
        var hash = 0
        for scalar in opening.company.unicodeScalars {
            hash = 31 &* hash &+ Int(scalar.value)
        }
        return palette[abs(hash) % palette.count]
    }
}
