import SwiftUI
import UIKit
import UserNotifications

/// Delegat aplikacji istnieje z dwóch powodów, których nie da się załatwić
/// samym SwiftUI: kategorie powiadomień i delegat muszą być gotowe przed
/// zakończeniem uruchamiania (inaczej akcja z powiadomienia, które wybudziło
/// aplikację, przepadnie), a `BGTaskScheduler` wymaga rejestracji dokładnie
/// w tym momencie.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let notificationDelegate = NotificationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        AppServices.shared.notifications.registerCategories()
        BackgroundRefresh.register()
        return true
    }
}

@main
struct PlatnosciApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppServices.shared.store)
                .task {
                    await AppServices.shared.store.bootstrap()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            Task { @MainActor in
                switch phase {
                case .active:
                    await AppServices.shared.store.refreshAfterReturningToForeground()
                case .background:
                    BackgroundRefresh.schedule()
                default:
                    break
                }
            }
        }
    }
}
