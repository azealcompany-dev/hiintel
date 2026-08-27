import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@main
struct HiringIntelApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _ = FeedStore.syncBundleIntoAppGroup()
        FeedStore.reloadTimelines()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    JobOpener.open(url)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active || phase == .background {
                _ = FeedStore.syncBundleIntoAppGroup()
                FeedStore.reloadTimelines()
            }
        }
    }
}

enum JobOpener {
    static func open(_ url: URL) {
        let resolved: URL
        if url.scheme == "hiringintel" {
            let id = url.pathComponents.last(where: { $0 != "/" }) ?? ""
            guard let match = FeedStore.load().openings.first(where: { $0.id == id }),
                  let jobURL = match.jobURL else { return }
            resolved = jobURL
        } else if url.scheme == "http" || url.scheme == "https" {
            resolved = url
        } else {
            return
        }
        #if os(iOS)
        UIApplication.shared.open(resolved)
        #elseif os(macOS)
        NSWorkspace.shared.open(resolved)
        #endif
    }
}
