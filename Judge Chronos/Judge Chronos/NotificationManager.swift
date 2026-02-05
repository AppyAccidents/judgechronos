import Foundation
import UserNotifications

enum NotificationManager {
    static let dailyReviewId = "daily-review-reminder"
    static let goalNudgeId = "goal-nudge-reminder"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted
        } catch {
            return false
        }
    }

    static func scheduleDailyReview(time: Date) async {
        guard await requestAuthorization() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Daily review"
        content.body = "Take 30 seconds to confirm today’s categories."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents(from: time), repeats: true)
        let request = UNNotificationRequest(identifier: dailyReviewId, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        await center.removePendingNotificationRequests(withIdentifiers: [dailyReviewId])
        do {
            try await center.add(request)
        } catch {
            // ignore scheduling errors
        }
    }

    static func scheduleGoalNudge(time: Date) async {
        guard await requestAuthorization() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Goal check-in"
        content.body = "How are you tracking against today’s goals?"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents(from: time), repeats: true)
        let request = UNNotificationRequest(identifier: goalNudgeId, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        await center.removePendingNotificationRequests(withIdentifiers: [goalNudgeId])
        do {
            try await center.add(request)
        } catch {
            // ignore scheduling errors
        }
    }

    static func clearDailyReview() async {
        let center = UNUserNotificationCenter.current()
        await center.removePendingNotificationRequests(withIdentifiers: [dailyReviewId])
    }

    static func clearGoalNudge() async {
        let center = UNUserNotificationCenter.current()
        await center.removePendingNotificationRequests(withIdentifiers: [goalNudgeId])
    }

    private static func dateComponents(from date: Date) -> DateComponents {
        let calendar = Calendar.current
        return calendar.dateComponents([.hour, .minute], from: date)
    }
}
