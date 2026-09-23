import Foundation

/// Odhaczenie leku albo przypomnienia niepłatnościowego w konkretnym terminie.
struct OccurrenceCheck: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var itemID: UUID
    var occurrenceKey: String
    var completedAt: Date
    var coversDate: Date

    init(
        id: UUID = UUID(),
        itemID: UUID,
        occurrenceKey: String,
        completedAt: Date = Date(),
        coversDate: Date
    ) {
        self.id = id
        self.itemID = itemID
        self.occurrenceKey = occurrenceKey
        self.completedAt = completedAt
        self.coversDate = coversDate
    }
}

/// Grupa leków, np. „LEKARSTWA”. W Przypomnieniach staje się osobną listą.
struct MedicationGroup: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    /// Nazwa listy w aplikacji Przypomnienia.
    var listName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Leki" : trimmed
    }
}

/// Jedna dawka w grupie, o stałej godzinie. Odhacza się osobno każdego dnia.
struct MedicationDose: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var groupID: UUID
    var name: String
    var time: TimeOfDay
    var isActive: Bool

    init(
        id: UUID = UUID(),
        groupID: UUID,
        name: String,
        time: TimeOfDay,
        isActive: Bool = true
    ) {
        self.id = id
        self.groupID = groupID
        self.name = name
        self.time = time
        self.isActive = isActive
    }
}

/// Plan lekcji jednej osoby, np. „Róża”.
struct LessonPlan: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    var listTitle: String {
        BoardNaming.lessonListTitle(name)
    }
}

/// Jeden blok w planie: dzień tygodnia i zakres godzin.
struct LessonBlock: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var planID: UUID
    var weekday: Int
    var start: TimeOfDay
    var end: TimeOfDay
    var note: String

    init(
        id: UUID = UUID(),
        planID: UUID,
        weekday: Int,
        start: TimeOfDay,
        end: TimeOfDay,
        note: String = ""
    ) {
        self.id = id
        self.planID = planID
        self.weekday = min(max(weekday, 1), 7)
        self.start = start
        self.end = end
        self.note = note
    }
}

enum BoardNaming {
    static func lessonListTitle(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("plan lekcji") {
            return trimmed
        }
        return "Plan lekcji \(trimmed)"
    }

    static func weekdayName(_ weekday: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.weekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index].localizedCapitalized
    }

    /// Poniedziałek jako pierwszy, zgodnie z `calendar.firstWeekday`.
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }
}
