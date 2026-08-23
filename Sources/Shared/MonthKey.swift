import Foundation

/// Identyfikator okresu rozliczeniowego (rok + miesiąc).
///
/// Osobny typ zamiast pary `Int`, bo dzięki temu kompilator pilnuje, że nigdzie
/// nie pomylimy kolejności argumentów, a logika przycinania dnia miesiąca
/// (31 lutego nie istnieje) siedzi w jednym miejscu.
struct MonthKey: Hashable, Comparable, Codable, Sendable, Identifiable {
    var year: Int
    var month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month], from: date)
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
    }

    var id: String {
        "\(year)-\(String(format: "%02d", month))"
    }

    static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// Przesunięcie o dowolną liczbę miesięcy, także wstecz.
    /// Liczone na indeksie miesiąca od zera, żeby przejście przez grudzień
    /// nie wymagało osobnego przypadku.
    func adding(months offset: Int) -> MonthKey {
        let absoluteMonth = year * 12 + (month - 1) + offset
        let normalizedYear = Int(floor(Double(absoluteMonth) / 12.0))
        let normalizedMonth = absoluteMonth - normalizedYear * 12
        return MonthKey(year: normalizedYear, month: normalizedMonth + 1)
    }

    func firstDay(calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return calendar.date(from: components)
    }

    func numberOfDays(calendar: Calendar) -> Int {
        guard let first = firstDay(calendar: calendar),
              let range = calendar.range(of: .day, in: .month, for: first)
        else { return 30 }
        return range.count
    }

    /// Konkretna data w tym miesiącu. Dzień jest przycinany do długości miesiąca,
    /// więc termin „31" w lutym wypada 28 lub 29 lutego, a nie w marcu.
    /// Stara wersja aplikacji obchodziła to ograniczeniem terminu do 1–28.
    func date(day: Int, time: TimeOfDay, calendar: Calendar) -> Date? {
        let clampedDay = min(max(day, 1), numberOfDays(calendar: calendar))
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = clampedDay
        components.hour = time.hour
        components.minute = time.minute
        return calendar.date(from: components)
    }

    func displayName(calendar: Calendar, locale: Locale = .current) -> String {
        guard let date = firstDay(calendar: calendar) else { return id }
        return date
            .formatted(.dateTime.month(.wide).year().locale(locale))
            .localizedCapitalized
    }
}

/// Godzina i minuta bez daty.
struct TimeOfDay: Hashable, Codable, Sendable {
    var hour: Int
    var minute: Int

    static let morning = TimeOfDay(hour: 9, minute: 0)

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    var formatted: String {
        String(format: "%02d:%02d", hour, minute)
    }
}
