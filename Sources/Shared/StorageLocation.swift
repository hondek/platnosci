import Foundation

/// Ustala, gdzie leży plik z danymi.
///
/// Jeśli aplikacja jest podpisana z uprawnieniem App Groups (płatne konto Apple),
/// dane trafiają do kontenera współdzielonego, żeby widget mógł je czytać.
/// Przy darmowym certyfikacie App Groups nie są dostępne, więc lądujemy w
/// prywatnym katalogu aplikacji. Aplikacja działa identycznie w obu wariantach —
/// różnica dotyczy wyłącznie widgetu.
enum StorageLocation {
    static let appGroupIdentifier = "group.com.example.platnosci"
    static let fileName = "payments.json"

    static var isUsingSharedContainer: Bool {
        sharedContainerURL() != nil
    }

    static func storeFileURL() -> URL {
        directoryURL().appendingPathComponent(fileName, isDirectory: false)
    }

    static func directoryURL() -> URL {
        let base = sharedContainerURL() ?? privateContainerURL()
        let directory = base.appendingPathComponent("PlatnosciStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func sharedContainerURL() -> URL? {
        #if APP_GROUP_ENABLED
        return FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
        #else
        return nil
        #endif
    }

    private static func privateContainerURL() -> URL {
        let manager = FileManager.default
        if let support = try? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return support
        }
        return manager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
    }
}
