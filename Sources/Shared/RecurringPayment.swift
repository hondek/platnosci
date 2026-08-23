import Foundation

/// Jak natarczywie aplikacja ma przypominać o nieopłaconej płatności.
///
/// iOS nie ma „przyklejonego" powiadomienia, które wisi na ekranie do
/// odwołania — jedyne, co da się zrobić bez zgody Apple na Critical Alerts,
/// to powtarzać powiadomienie tak długo, aż użytkownik odhaczy płatność.
enum ReminderIntensity: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Jedno przypomnienie w terminie i cisza.
    case single
    /// Raz dziennie, dopóki nie zapłacisz.
    case daily
    /// Trzy razy dziennie, dopóki nie zapłacisz. Wartość domyślna.
    case persistent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: return "Jedno przypomnienie"
        case .daily: return "Codziennie"
        case .persistent: return "Natarczywie (3× dziennie)"
        }
    }

    var explanation: String {
        switch self {
        case .single:
            return "Jedno powiadomienie w dniu terminu."
        case .daily:
            return "Jedno powiadomienie dziennie, dopóki nie oznaczysz płatności."
        case .persistent:
            return "Trzy powiadomienia dziennie, dopóki nie oznaczysz płatności. Plakietka na ikonie wisi cały czas."
        }
    }

    /// Ile godzin po godzinie bazowej wysyłać kolejne powiadomienia tego dnia.
    var hourOffsets: [Int] {
        switch self {
        case .single: return [0]
        case .daily: return [0]
        case .persistent: return [0, 4, 9]
        }
    }

    /// Przez ile dni od terminu ponawiać przypomnienia.
    var windowDays: Int {
        switch self {
        case .single: return 14
        case .daily: return 21
        case .persistent: return 21
        }
    }

    /// Górny limit powiadomień na jeden okres rozliczeniowy.
    var maxOccurrences: Int {
        switch self {
        case .single: return 1
        case .daily: return 21
        case .persistent: return 45
        }
    }
}

/// Stała płatność powtarzająca się co miesiąc.
struct RecurringPayment: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var amount: Money
    var note: String
    /// Dzień miesiąca, 1–31. Przycinany do długości konkretnego miesiąca.
    var dueDay: Int
    var reminderTime: TimeOfDay
    var intensity: ReminderIntensity
    var isActive: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        amount: Money,
        note: String = "",
        dueDay: Int = 10,
        reminderTime: TimeOfDay = .morning,
        intensity: ReminderIntensity = .persistent,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.note = note
        self.dueDay = min(max(dueDay, 1), 31)
        self.reminderTime = reminderTime
        self.intensity = intensity
        self.isActive = isActive
        self.createdAt = createdAt
    }

    /// Ręczna dekodera z wartościami domyślnymi dla brakujących pól.
    /// Bez tego dodanie nowego pola w przyszłej wersji wysypałoby dekodowanie
    /// i po cichu wyczyściło całą historię.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Money.self, forKey: .amount)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        dueDay = min(max(try container.decodeIfPresent(Int.self, forKey: .dueDay) ?? 10, 1), 31)
        reminderTime = try container.decodeIfPresent(TimeOfDay.self, forKey: .reminderTime) ?? .morning
        intensity = try container.decodeIfPresent(ReminderIntensity.self, forKey: .intensity) ?? .persistent
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// Zapis faktu opłacenia konkretnej płatności w konkretnym miesiącu.
///
/// Rekord istnieje tylko wtedy, gdy płatność została opłacona — brak rekordu
/// oznacza „nieopłacone". Jest to prostsze niż rekord z opcjonalną datą, bo
/// nie da się reprezentować stanu niemożliwego.
struct PaymentEntry: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var paymentID: UUID
    var period: MonthKey
    var paidAt: Date
    /// Kwota z chwili zapłaty. Bez tego zmiana kwoty płatności przepisywałaby
    /// wstecznie całą historię — to był błąd w pierwszej wersji aplikacji.
    var amountPaid: Money
    /// Nazwa z chwili zapłaty, żeby historia przetrwała zmianę nazwy i usunięcie
    /// płatności.
    var paymentName: String

    init(
        id: UUID = UUID(),
        paymentID: UUID,
        period: MonthKey,
        paidAt: Date = Date(),
        amountPaid: Money,
        paymentName: String
    ) {
        self.id = id
        self.paymentID = paymentID
        self.period = period
        self.paidAt = paidAt
        self.amountPaid = amountPaid
        self.paymentName = paymentName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        paymentID = try container.decode(UUID.self, forKey: .paymentID)
        period = try container.decode(MonthKey.self, forKey: .period)
        paidAt = try container.decode(Date.self, forKey: .paidAt)
        amountPaid = try container.decodeIfPresent(Money.self, forKey: .amountPaid) ?? .zero
        paymentName = try container.decodeIfPresent(String.self, forKey: .paymentName) ?? ""
    }
}
