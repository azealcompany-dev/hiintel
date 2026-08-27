import SwiftUI
#if os(iOS)
import BackgroundTasks
import UIKit
#elseif os(macOS)
import AppKit
#endif

@main
struct HiringIntelApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Self.registerBackgroundRefresh()
        _ = FeedStore.seedAppGroupIfNeeded()
        Task {
            _ = await FeedStore.fetchRemote(
                timeout: FeedStore.hostFetchTimeout,
                reloadOnSuccess: true
            )
            FeedStore.scheduleBackgroundRefresh()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    JobOpener.open(url)
                }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                _ = FeedStore.seedAppGroupIfNeeded()
                Task {
                    _ = await FeedStore.fetchRemote(
                        timeout: FeedStore.hostFetchTimeout,
                        reloadOnSuccess: true
                    )
                    FeedStore.scheduleBackgroundRefresh()
                }
            }
        }
    }

    private static func registerBackgroundRefresh() {
        #if os(iOS)
        // Must register before UIApplication finishes launching, or iOS kills
        // the process when a previously scheduled BGAppRefresh task is delivered.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: FeedStore.backgroundRefreshID,
            using: nil
        ) { task in
            Task {
                let feed = await FeedStore.fetchRemote(
                    timeout: FeedStore.hostFetchTimeout,
                    reloadOnSuccess: true
                )
                AppBadge.refresh(from: feed ?? FeedStore.load())
                FeedStore.scheduleBackgroundRefresh()
                task.setTaskCompleted(success: feed != nil)
            }
        }
        #endif
    }
}

enum JobOpener {
    static func open(_ url: URL) {
        if url.scheme == "hiringintel" {
            let id = url.pathComponents.last(where: { $0 != "/" }) ?? ""
            NotificationCenter.default.post(name: .hiintelOpenJob, object: id)
            return
        }
        let resolved: URL
        if url.scheme == "http" || url.scheme == "https" {
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
