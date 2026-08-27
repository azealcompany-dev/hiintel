import Foundation
import UserNotifications

enum ReferralNudge {
    static func identifier(for id: String) -> String { "hiintel.referral.\(id)" }

    static func requestAccess() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func schedule(opening: Opening) {
        requestAccess()
        cancel(id: opening.id)
        let content = UNMutableNotificationContent()
        content.title = "HiIntel"
        content.body = "Ask for a referral at \(opening.company)."
        content.sound = .default
        content.userInfo = ["openingID": opening.id]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5 * 24 * 60 * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: opening.id),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: id)])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier(for: id)])
    }
}
