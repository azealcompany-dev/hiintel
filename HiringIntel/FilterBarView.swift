import SwiftUI

struct FilterChip: View {
    let title: String
    var count: Int? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .opacity(0.8)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                selected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06),
                in: Capsule()
            )
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .overlay(
                Capsule()
                    .strokeBorder(selected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
    }
}

struct FilterBarView: View {
    let feed: OpeningsFeed
    let familyCounts: [String: Int]
    let sourceLabel: String
    let isStale: Bool
    @Binding var familiesRaw: String
    @Binding var whereRaw: String
    @Binding var whenRaw: String
    @Binding var sortRaw: String
    @Binding var viewRaw: String
    @Binding var segmentRaw: String
    @Binding var workplaceRaw: String
    @Binding var metroRaw: String
    var hasActiveFilters: Bool
    var onClear: () -> Void

    private var selectedFamilies: Set<String> {
        Set(familiesRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private var segmentPresent: Set<String> {
        Set(feed.openings.compactMap(\.segment))
    }

    private var workplacePresent: Set<String> {
        Set(feed.openings.compactMap(\.workplace))
    }

    private var metroPresent: Set<MetroKind> {
        Set(feed.openings.compactMap(MetroKind.classify))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chipRow {
                ForEach(RoleFamily.allCases) { family in
                    FilterChip(
                        title: family.rawValue,
                        count: familyCounts[family.rawValue] ?? 0,
                        selected: selectedFamilies.contains(family.rawValue)
                    ) {
                        toggleFamily(family.rawValue)
                    }
                }
            }

            chipRow {
                ForEach(WhereKind.allCases) { kind in
                    FilterChip(title: kind.title, selected: whereRaw == kind.rawValue) {
                        whereRaw = whereRaw == kind.rawValue ? "" : kind.rawValue
                    }
                }
                ForEach(WhenKind.allCases) { kind in
                    FilterChip(title: kind.title, selected: whenRaw == kind.rawValue) {
                        whenRaw = whenRaw == kind.rawValue ? "" : kind.rawValue
                    }
                }
            }

            if !segmentPresent.isEmpty {
                chipRow {
                    ForEach(SegmentKind.allCases.filter { segmentPresent.contains($0.rawValue) }) { kind in
                        FilterChip(title: kind.title, selected: segmentRaw == kind.rawValue) {
                            segmentRaw = segmentRaw == kind.rawValue ? "" : kind.rawValue
                        }
                    }
                }
            }

            if !workplacePresent.isEmpty {
                chipRow {
                    ForEach(WorkplaceKind.allCases.filter { workplacePresent.contains($0.rawValue) }) { kind in
                        FilterChip(title: kind.title, selected: workplaceRaw == kind.rawValue) {
                            workplaceRaw = workplaceRaw == kind.rawValue ? "" : kind.rawValue
                        }
                    }
                }
            }

            if !metroPresent.isEmpty {
                chipRow {
                    ForEach(MetroKind.allCases.filter { metroPresent.contains($0) }) { kind in
                        FilterChip(title: kind.title, selected: metroRaw == kind.rawValue) {
                            metroRaw = metroRaw == kind.rawValue ? "" : kind.rawValue
                        }
                    }
                }
            }

            chipRow {
                ForEach(SortMode.allCases) { mode in
                    FilterChip(title: mode.title, selected: sortRaw == mode.rawValue) {
                        sortRaw = mode.rawValue
                    }
                }
                ForEach(ReaderViewMode.allCases) { mode in
                    FilterChip(title: mode.title, selected: viewRaw == mode.rawValue) {
                        viewRaw = mode.rawValue
                    }
                }
                if hasActiveFilters {
                    Button("Clear", action: onClear)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .padding(.leading, 4)
                }
            }

            Text(statsLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

            if isStale {
                Text("Feed looks stale — last update is older than 36 hours.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var statsLine: String {
        let openings = feed.openings
        let sdr = openings.filter { $0.roleFamily == "SDR" }.count
        let bdr = openings.filter { $0.roleFamily == "BDR" }.count
        let ae = openings.filter { $0.roleFamily == "AE" }.count
        return "\(openings.count) \(sourceLabel) · \(sdr) SDR · \(bdr) BDR · \(ae) AE · \(FeedDates.updatedLabel(feed.updatedAt))"
    }

    @ViewBuilder
    private func chipRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
        }
    }

    private func toggleFamily(_ family: String) {
        var set = selectedFamilies
        if set.contains(family) {
            set.remove(family)
        } else {
            set.insert(family)
        }
        familiesRaw = set.sorted().joined(separator: ",")
    }
}
