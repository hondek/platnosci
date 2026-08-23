import Foundation

/// Ustawienia aplikacji trzymane razem z danymi.
struct AppSettings: Hashable, Codable, Sendable {
    var currencyCode: String
    /// Na ile miesięcy w przód planować powiadomienia.
    var lookaheadMonths: Int
    /// Czy przykładowe płatności zostały już raz wstawione.
    /// Bez tej flagi usunięcie wszystkich płatności powodowałoby, że przy
    /// następnym starcie przykłady wracają — tak zachowywała się pierwsza wersja.
    var didSeedExamples: Bool

    static let `default` = AppSettings(
        currencyCode: "PLN",
        lookaheadMonths: 2,
        didSeedExamples: false
    )

    init(currencyCode: String, lookaheadMonths: Int, didSeedExamples: Bool) {
        self.currencyCode = currencyCode
        self.lookaheadMonths = lookaheadMonths
        self.didSeedExamples = didSeedExamples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? "PLN"
        lookaheadMonths = try container.decodeIfPresent(Int.self, forKey: .lookaheadMonths) ?? 2
        didSeedExamples = try container.decodeIfPresent(Bool.self, forKey: .didSeedExamples) ?? false
    }
}

/// Cała zawartość bazy w jednym, wersjonowanym dokumencie.
///
/// Wersja schematu jest zapisana w pliku, więc przyszła migracja danych jest
/// możliwa bez zgadywania formatu.
struct PaymentsSnapshot: Hashable, Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var payments: [RecurringPayment]
    var entries: [PaymentEntry]
    var settings: AppSettings

    static let empty = PaymentsSnapshot(
        schemaVersion: currentSchemaVersion,
        payments: [],
        entries: [],
        settings: .default
    )

    init(
        schemaVersion: Int = PaymentsSnapshot.currentSchemaVersion,
        payments: [RecurringPayment],
        entries: [PaymentEntry],
        settings: AppSettings
    ) {
        self.schemaVersion = schemaVersion
        self.payments = payments
        self.entries = entries
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        payments = try container.decodeIfPresent([RecurringPayment].self, forKey: .payments) ?? []
        entries = try container.decodeIfPresent([PaymentEntry].self, forKey: .entries) ?? []
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? .default
    }

    /// Punkt zaczepienia dla przyszłych migracji. Dziś tylko podnosi numer
    /// wersji, ale kiedy schemat się zmieni, przekształcenia trafiają tutaj.
    func migratedToCurrentSchema() -> PaymentsSnapshot {
        guard schemaVersion < Self.currentSchemaVersion else { return self }
        var migrated = self
        migrated.schemaVersion = Self.currentSchemaVersion
        return migrated
    }

    static func exampleSeed() -> [RecurringPayment] {
        [
            RecurringPayment(
                name: "Marek",
                amount: Money(300),
                dueDay: 10,
                reminderTime: TimeOfDay(hour: 9, minute: 0),
                intensity: .persistent
            ),
            RecurringPayment(
                name: "Andrzej",
                amount: Money(2000),
                dueDay: 10,
                reminderTime: TimeOfDay(hour: 9, minute: 0),
                intensity: .persistent
            )
        ]
    }
}
