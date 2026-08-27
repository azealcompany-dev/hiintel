import Foundation
#if os(iOS)
import UIKit
import UserNotifications
#elseif os(macOS)
import AppKit
#endif

enum AppBadge {
    static func setCount(_ count: Int) {
        let value = max(0, count)
        #if os(iOS)
        Task { @MainActor in
            try? await UNUserNotificationCenter.current().setBadgeCount(value)
            UIApplication.shared.applicationIconBadgeNumber = value
        }
        #elseif os(macOS)
        DispatchQueue.main.async {
            NSApplication.shared.dockTile.badgeLabel = value > 0 ? "\(value)" : nil
        }
        #endif
    }

    static func refresh(from feed: OpeningsFeed) {
        setCount(OpeningMarks.newCount(in: feed, since: OpeningMarks.lastAppOpen))
    }

    static func clear() {
        setCount(0)
    }
}
