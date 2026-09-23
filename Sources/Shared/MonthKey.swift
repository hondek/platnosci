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

    init?(parsing id: String) {
        let parts = id.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month)
        else { return nil }
        self.init(year: year, month: month)
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

/// Konkretny dzień, używany przy lekach i tygodniowych przypomnieniach.
struct DayKey: Hashable, Codable, Sendable, Comparable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
        self.day = components.day ?? 1
    }

    init?(parsing id: String) {
        let parts = id.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    var id: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    func date(time: TimeOfDay, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = time.hour
        components.minute = time.minute
        return calendar.date(from: components)
    }

    func startOfDay(calendar: Calendar) -> Date? {
        date(time: TimeOfDay(hour: 0, minute: 0), calendar: calendar)
    }
}

/// Godzina i minuta bez daty.
struct TimeOfDay: Hashable, Comparable, Codable, Sendable {
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

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}
