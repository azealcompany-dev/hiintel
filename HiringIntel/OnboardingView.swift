import SwiftUI

struct OnboardingView: View {
    let companies: [String]
    @Binding var familiesRaw: String
    let onPin: (Set<String>) -> Void
    let onDone: () -> Void

    @State private var families: Set<String> = ["SDR", "BDR", "AE"]
    @State private var pinned: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("A daily reader for SDR, BDR, and AE openings. No accounts. No scraping.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Families")
                            .font(.headline)
                        HStack {
                            ForEach(RoleFamily.allCases) { family in
                                FilterChip(
                                    title: family.rawValue,
                                    selected: families.contains(family.rawValue)
                                ) {
                                    if families.contains(family.rawValue) {
                                        families.remove(family.rawValue)
                                    } else {
                                        families.insert(family.rawValue)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pin companies")
                            .font(.headline)
                        Text("Pinned companies sort first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        FlexibleCompanyPins(companies: companies, pinned: $pinned)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Widget")
                            .font(.headline)
                        Text("Add the medium HiIntel widget from the Home Screen for new-today count plus the next pinned opening.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button("Start reading") {
                        familiesRaw = families.sorted().joined(separator: ",")
                        onPin(pinned)
                        onDone()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .navigationTitle("HiIntel")
        }
    }
}

private struct FlexibleCompanyPins: View {
    let companies: [String]
    @Binding var pinned: Set<String>

    var body: some View {
        let shown = Array(companies.prefix(18))
        VStack(alignment: .leading, spacing: 8) {
            ForEach(shown, id: \.self) { name in
                FilterChip(title: name, selected: pinned.contains(name)) {
                    if pinned.contains(name) {
                        pinned.remove(name)
                    } else {
                        pinned.insert(name)
                    }
                }
            }
        }
    }
}
