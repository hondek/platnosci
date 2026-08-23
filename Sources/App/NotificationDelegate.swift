import Foundation
import UserNotifications

/// Odbiera powiadomienia i akcje z nich.
///
/// Klasa nie jest przypisana do żadnego aktora — pracę przekazuje jawnie na
/// główny aktor przez `await`. Dane z `UNNotificationResponse` wyłuskujemy od
/// razu, bo ten typ nie jest `Sendable` i nie wolno go przenosić między
/// kontekstami współbieżności.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    /// Pokazuje powiadomienie także wtedy, gdy aplikacja jest właśnie otwarta.
    /// Bez tego przypomnienie zostałoby po cichu pominięte.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = Self.payload(from: response)
        await AppServices.shared.handleNotificationAction(payload)
    }

    private static func payload(
        from response: UNNotificationResponse
    ) -> NotificationActionPayload {
        let content = response.notification.request.content
        let userInfo = content.userInfo

        let paymentID = (userInfo[NotificationService.UserInfoKey.paymentID] as? String)
            .flatMap(UUID.init(uuidString:))

        var period: MonthKey?
        if let year = userInfo[NotificationService.UserInfoKey.periodYear] as? Int,
           let month = userInfo[NotificationService.UserInfoKey.periodMonth] as? Int {
            period = MonthKey(year: year, month: month)
        }

        return NotificationActionPayload(
            actionIdentifier: response.actionIdentifier,
            paymentID: paymentID,
            period: period,
            title: content.title,
            body: content.body
        )
    }
}
