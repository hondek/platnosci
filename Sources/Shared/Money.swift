import Foundation

/// Kwota pieniędzy oparta na `Decimal`, a nie na `Double`.
/// `Double` nie potrafi dokładnie zapisać wartości takich jak 0.1, więc sumowanie
/// kwot prowadzi do groszowych rozjazdów. `Decimal` jest tu dokładny.
struct Money: Hashable, Comparable, Codable, Sendable {
    var value: Decimal

    static let zero = Money(value: 0)

    init(value: Decimal) {
        self.value = value
    }

    init(_ integer: Int) {
        self.value = Decimal(integer)
    }

    static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.value < rhs.value
    }

    static func + (lhs: Money, rhs: Money) -> Money {
        Money(value: lhs.value + rhs.value)
    }

    static func - (lhs: Money, rhs: Money) -> Money {
        Money(value: lhs.value - rhs.value)
    }

    var isZero: Bool {
        value == 0
    }

    /// Wartość w groszach — używana do budowania stabilnych identyfikatorów
    /// powiadomień, żeby zmiana kwoty unieważniła stary, zaplanowany komunikat.
    var minorUnits: Int {
        NSDecimalNumber(decimal: value * 100).intValue
    }

    func formatted(currencyCode: String) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    /// Kodujemy jako pojedynczą liczbę, a nie jako obiekt `{"value": ...}`.
    /// Dzięki temu plik z danymi jest czytelny i łatwiej go ręcznie naprawić.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(Decimal.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension Sequence where Element == Money {
    func total() -> Money {
        reduce(Money.zero, +)
    }
}
