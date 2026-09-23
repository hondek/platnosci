import BackgroundTasks
import Foundation

/// Odświeżanie planu przypomnień bez udziału użytkownika.
///
/// iOS nie pozwala aplikacjom trzymać własnego demona ani niczego w rodzaju
/// crona. `BGAppRefreshTask` to najbliższy odpowiednik: system sam budzi
/// aplikację na kilka sekund, kiedy uzna to za stosowne. Wystarczy to, żeby
/// przesuwać okno zaplanowanych powiadomień do przodu, więc przypomnienia nie
/// wygasają po wyczerpaniu zaplanowanej puli.
enum BackgroundRefresh {
    static let taskIdentifier = "com.hondek.platnosci.refresh"

    /// Musi zostać wywołane przed zakończeniem uruchamiania aplikacji,
    /// inaczej system zgłasza wyjątek.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            handle(task)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGTask) {
        // Kolejne zadanie zamawiamy od razu — jeśli tego nie zrobimy,
        // odświeżanie w tle wykona się dokładnie raz i nigdy więcej.
        schedule()

        let work = Task { @MainActor in
            await AppServices.shared.performBackgroundRefresh()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
