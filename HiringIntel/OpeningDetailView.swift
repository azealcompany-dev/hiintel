import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct OpeningDetailView: View {
    let opening: Opening
    let feedUpdated: Date?
    @ObservedObject var tracker: OpeningTracker

    @State private var copied = false
    @State private var offerMarkApplied = false

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
        .confirmationDialog(
            "Mark as applied?",
            isPresented: $offerMarkApplied,
            titleVisibility: .visible
        ) {
            Button("Mark applied") { tracker.markApplied(opening.id) }
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
            tracker.toggleSaved(opening.id)
        } label: {
            Label(
                tracker.isSaved(opening.id) ? "Saved" : "Save",
                systemImage: tracker.isSaved(opening.id) ? "bookmark.fill" : "bookmark"
            )
        }
        .buttonStyle(.bordered)
        .tint(tracker.isSaved(opening.id) ? .accentColor : .secondary)

        Button {
            tracker.toggleApplied(opening.id)
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

    private func copyLink() {
        guard !opening.url.isEmpty else { return }
        #if os(iOS)
        UIPasteboard.general.string = opening.url
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(opening.url, forType: .string)
        #endif
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
}
