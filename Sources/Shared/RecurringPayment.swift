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

/// Czy to rachunek, który płacę, pieniądze do odebrania, czy zwykłe przypomnienie.
enum LedgerKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case outgoing
    case incoming
    case chore

    var id: String { rawValue }

    var boardTitle: String {
        switch self {
        case .outgoing: return "Płatności"
        case .incoming: return "Należności"
        case .chore: return "Przypomnienia"
        }
    }

    var newItemTitle: String {
        switch self {
        case .outgoing: return "Nowa płatność"
        case .incoming: return "Nowa należność"
        case .chore: return "Nowe przypomnienie"
        }
    }

    var editItemTitle: String {
        switch self {
        case .outgoing: return "Edytuj płatność"
        case .incoming: return "Edytuj należność"
        case .chore: return "Edytuj przypomnienie"
        }
    }

    var doneButton: String {
        switch self {
        case .outgoing: return "Oznacz jako zapłacone"
        case .incoming: return "Oznacz jako odebrane"
        case .chore: return "Zrobione"
        }
    }

    var doneLabel: String {
        switch self {
        case .outgoing: return "Zapłacone"
        case .incoming: return "Odebrane"
        case .chore: return "Zrobione"
        }
    }

    var summaryTitle: String {
        switch self {
        case .outgoing: return "Podsumowanie miesiąca"
        case .incoming: return "Do odebrania w tym miesiącu"
        case .chore: return "Przypomnienia"
        }
    }

    var completeLabel: String {
        switch self {
        case .outgoing: return "Wszystko opłacone"
        case .incoming: return "Wszystko odebrane"
        case .chore: return "Wszystko zrobione"
        }
    }

    var progressNoun: String {
        switch self {
        case .outgoing: return "opłaconych"
        case .incoming: return "odebranych"
        case .chore: return "zrobionych"
        }
    }

    var reminderListName: String {
        switch self {
        case .outgoing: return "Płatności"
        case .incoming: return "Należności"
        case .chore: return "Przypomnienia"
        }
    }

    var handlesMoney: Bool {
        self != .chore
    }
}

/// Jak często wraca pozycja. Płatności są miesięczne, przypomnienie może być tygodniowe.
enum ItemCadence: String, Codable, CaseIterable, Sendable, Identifiable {
    case monthly
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: return "Co miesiąc"
        case .weekly: return "Co tydzień"
        }
    }
}

/// Stała płatność, należność albo przypomnienie.
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
    var kind: LedgerKind
    var cadence: ItemCadence
    /// Dzień tygodnia w numeracji kalendarza (1 = niedziela … 7 = sobota). Tylko przy `cadence == .weekly`.
    var weekday: Int?
    /// Godziny alarmów. Puste pole uzupełnia dekoder godziną `reminderTime`.
    var reminderTimes: [TimeOfDay]

    init(
        id: UUID = UUID(),
        name: String,
        amount: Money,
        note: String = "",
        dueDay: Int = 10,
        reminderTime: TimeOfDay = .morning,
        intensity: ReminderIntensity = .persistent,
        isActive: Bool = true,
        createdAt: Date = Date(),
        kind: LedgerKind = .outgoing,
        cadence: ItemCadence = .monthly,
        weekday: Int? = nil,
        reminderTimes: [TimeOfDay]? = nil
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
        self.kind = kind
        self.cadence = cadence
        if let weekday {
            self.weekday = min(max(weekday, 1), 7)
        } else {
            self.weekday = nil
        }
        let provided = reminderTimes ?? []
        let times = (provided.isEmpty ? [reminderTime] : provided).sorted()
        self.reminderTimes = times
        self.reminderTime = times[0]
    }

    /// Godziny, o których ma zadzwonić alarm. Zawsze co najmniej jedna.
    var effectiveTimes: [TimeOfDay] {
        let times = reminderTimes.isEmpty ? [reminderTime] : reminderTimes
        var seen: Set<Int> = []
        return times.sorted().filter { seen.insert($0.hour * 60 + $0.minute).inserted }
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
        kind = try container.decodeIfPresent(LedgerKind.self, forKey: .kind) ?? .outgoing
        cadence = try container.decodeIfPresent(ItemCadence.self, forKey: .cadence) ?? .monthly
        if let decodedWeekday = try container.decodeIfPresent(Int.self, forKey: .weekday) {
            weekday = min(max(decodedWeekday, 1), 7)
        } else {
            weekday = nil
        }
        let decodedTimes = try container.decodeIfPresent([TimeOfDay].self, forKey: .reminderTimes) ?? []
        reminderTimes = decodedTimes.isEmpty ? [reminderTime] : decodedTimes.sorted()
        reminderTime = reminderTimes[0]
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
    /// Dzień, za który jest ta wpłata. Osobno od chwili odhaczenia.
    var coversDate: Date?
    var kind: LedgerKind

    init(
        id: UUID = UUID(),
        paymentID: UUID,
        period: MonthKey,
        paidAt: Date = Date(),
        amountPaid: Money,
        paymentName: String,
        coversDate: Date? = nil,
        kind: LedgerKind = .outgoing
    ) {
        self.id = id
        self.paymentID = paymentID
        self.period = period
        self.paidAt = paidAt
        self.amountPaid = amountPaid
        self.paymentName = paymentName
        self.coversDate = coversDate
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        paymentID = try container.decode(UUID.self, forKey: .paymentID)
        period = try container.decode(MonthKey.self, forKey: .period)
        paidAt = try container.decode(Date.self, forKey: .paidAt)
        amountPaid = try container.decodeIfPresent(Money.self, forKey: .amountPaid) ?? .zero
        paymentName = try container.decodeIfPresent(String.self, forKey: .paymentName) ?? ""
        coversDate = try container.decodeIfPresent(Date.self, forKey: .coversDate)
        kind = try container.decodeIfPresent(LedgerKind.self, forKey: .kind) ?? .outgoing
    }
}
