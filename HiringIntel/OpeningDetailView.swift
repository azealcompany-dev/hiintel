import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct OpeningDetailView: View {
    let opening: Opening
    let feed: OpeningsFeed
    let feedUpdated: Date?
    @ObservedObject var tracker: OpeningTracker

    @State private var copied = false
    @State private var copiedNote = false
    @State private var copiedProof = false
    @State private var copiedReferral = false
    @State private var offerMarkApplied = false
    @State private var noteText = ""
    @State private var dateValue = Date()
    @State private var hasDate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                meta
                if !opening.companyBriefPlain.isEmpty {
                    Text(opening.companyBriefPlain)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                actions
                openPosting
                reachOut
                playbook
                tools
                followUpFields
                similar
                if !opening.lookingForPlain.isEmpty {
                    Divider()
                    Text("Looking for")
                        .font(.headline)
                    Text(opening.lookingForPlain)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle(opening.role)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            noteText = tracker.note(for: opening.id)
            if let iso = tracker.date(for: opening.id), let parsed = FeedDates.parsePosted(iso) {
                dateValue = parsed
                hasDate = true
            }
        }
        .confirmationDialog(
            "Mark as applied?",
            isPresented: $offerMarkApplied,
            titleVisibility: .visible
        ) {
            Button("Mark applied") { tracker.markApplied(opening) }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("You opened the posting for \(opening.role) at \(opening.company).")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(opening.companyInitials)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(opening.role)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                Text(opening.company)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if opening.isClosed {
                    Text("Closed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let line = opening.hiringManager?.displayLine {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button {
                    openOptional(HiringOutreach.findManagerURL(for: opening))
                } label: {
                    Label("Find hiring manager", systemImage: "person.crop.circle.badge.magnifyingglass")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if !opening.roleFamily.isEmpty {
                    Text(opening.roleFamily)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                if opening.isNew(relativeTo: feedUpdated) {
                    Text("New")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 0)
                if !opening.postedAt.isEmpty {
                    Text(FeedDates.relativePosted(opening.postedAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !opening.location.isEmpty {
                Label(opening.location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actionButtons }
            VStack(alignment: .leading, spacing: 8) { actionButtons }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            _ = tracker.toggleSaved(opening)
        } label: {
            Label(
                tracker.isSaved(opening.id) ? "Saved" : "Save",
                systemImage: tracker.isSaved(opening.id) ? "bookmark.fill" : "bookmark"
            )
        }
        .buttonStyle(.bordered)
        .tint(tracker.isSaved(opening.id) ? .accentColor : .secondary)

        Button {
            _ = tracker.toggleApplied(opening)
        } label: {
            Label(
                tracker.isApplied(opening.id) ? "Applied" : "Mark applied",
                systemImage: tracker.isApplied(opening.id) ? "checkmark.circle.fill" : "checkmark.circle"
            )
        }
        .buttonStyle(.bordered)
        .tint(tracker.isApplied(opening.id) ? .green : .secondary)

        Button {
            copyLink()
        } label: {
            Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "link")
        }
        .buttonStyle(.bordered)
        .disabled(opening.url.isEmpty)
    }

    private var openPosting: some View {
        Button {
            openPostingAndOfferApplied()
        } label: {
            Label("Open posting", systemImage: "arrow.up.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(opening.jobURL == nil)
        .foregroundStyle(.secondary)
    }

    private var reachOut: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reach out")
                .font(.headline)
            Button {
                openPostingAndOfferApplied()
            } label: {
                Label("Apply first", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(opening.jobURL == nil)

            Button {
                openOptional(HiringOutreach.messageURL(for: opening))
            } label: {
                Label("Message on LinkedIn", systemImage: "ellipsis.message")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                openOptional(HiringOutreach.referralURL(for: opening))
            } label: {
                Label("Ask for a referral", systemImage: "person.2")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                copyNote()
            } label: {
                Label(copiedNote ? "Copied note" : "Copy note", systemImage: copiedNote ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                copyProof()
            } label: {
                Label(copiedProof ? "Copied proof" : "Copy proof", systemImage: copiedProof ? "checkmark" : "text.badge.checkmark")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                copyReferralAsk()
            } label: {
                Label(copiedReferral ? "Copied ask" : "Copy referral ask", systemImage: copiedReferral ? "checkmark" : "envelope")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var followUpFields: some View {
        if tracker.isSaved(opening.id) || tracker.isApplied(opening.id) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Follow-up")
                    .font(.headline)
                TextField("Referral name or note", text: $noteText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: noteText) { _, value in
                        tracker.setNote(value, for: opening.id)
                    }
                Toggle("Interview / follow-up date", isOn: $hasDate)
                    .onChange(of: hasDate) { _, on in
                        if on {
                            tracker.setDate(isoDate(dateValue), for: opening.id)
                        } else {
                            tracker.setDate(nil, for: opening.id)
                        }
                    }
                if hasDate {
                    DatePicker("Date", selection: $dateValue, displayedComponents: .date)
                        .onChange(of: dateValue) { _, value in
                            tracker.setDate(isoDate(value), for: opening.id)
                        }
                }
                Toggle("Follow-up done", isOn: followUpBinding)
            }
        }
    }

    private var followUpBinding: Binding<Bool> {
        Binding(
            get: { tracker.isFollowUpDone(opening.id) },
            set: { tracker.markFollowUpDone(opening.id, done: $0) }
        )
    }

    private var similar: some View {
        let matches = OpeningQuery.similar(to: opening, in: feed.openings)
        return Group {
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Similar openings")
                        .font(.headline)
                    ForEach(matches) { other in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(other.role)
                                .font(.subheadline.weight(.medium))
                            Text("\(other.company) · \(other.shortLocation)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var playbook: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playbook")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Apply first")
                Text("2. LinkedIn note the same day")
                Text("3. If no reply in ~5 days, ask an employee for a referral")
            }
            .font(.subheadline)
            Text("Do not sequence hiring managers like prospects.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools")
                .font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { toolButtons }
                VStack(alignment: .leading, spacing: 8) { toolButtons }
            }
        }
    }

    @ViewBuilder
    private var toolButtons: some View {
        toolButton("LinkedIn", url: HiringOutreach.findManagerURL(for: opening))
        toolButton(
            "Sales Navigator",
            url: HiringOutreach.salesNavigatorSearch(HiringOutreach.findManagerKeywords(for: opening))
        )
        toolButton("The Org", url: HiringOutreach.theOrgSearch(opening.company))
    }

    private func toolButton(_ title: String, url: URL?) -> some View {
        Button(title) { openOptional(url) }
            .buttonStyle(.bordered)
            .disabled(url == nil)
            .controlSize(.small)
    }

    private func copyLink() {
        guard !opening.url.isEmpty else { return }
        copyToPasteboard(opening.url)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copied = false
        }
    }

    private func openPostingAndOfferApplied() {
        guard let url = opening.jobURL else { return }
        JobOpener.open(url)
        if !tracker.isApplied(opening.id) {
            offerMarkApplied = true
        }
    }

    private func openOptional(_ url: URL?) {
        guard let url else { return }
        JobOpener.open(url)
    }

    private func copyNote() {
        flashCopy(HiringOutreach.note(for: opening)) { copiedNote = $0 }
    }

    private func copyProof() {
        flashCopy(HiringOutreach.proof(for: opening)) { copiedProof = $0 }
    }

    private func copyReferralAsk() {
        flashCopy(HiringOutreach.referralAsk(for: opening)) { copiedReferral = $0 }
    }

    private func flashCopy(_ string: String, flag: @escaping (Bool) -> Void) {
        copyToPasteboard(string)
        flag(true)
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            flag(false)
        }
    }

    private func isoDate(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return "" }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private func copyToPasteboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
