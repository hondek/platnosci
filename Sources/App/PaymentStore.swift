import Foundation
import Observation
import UserNotifications

/// Jedyne miejsce, w którym żyje stan aplikacji.
///
/// Zmiany zapisują się na dysk i od razu trafiają do aplikacji Przypomnienia.
/// Odhaczenie wpisu po stronie systemu jest wciągane przy najbliższym odświeżeniu.
@MainActor
@Observable
final class PaymentStore {
    private let repository: PaymentRepository
    private let notifications: NotificationService
    private let reminders: RemindersService
    private let calendar: Calendar

    private(set) var snapshot: PaymentsSnapshot = .empty
    private(set) var storageError: String?
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var remindersAccessGranted: Bool? = nil
    private(set) var remindersError: String?
    private(set) var scheduledReminderCount: Int = 0
    private(set) var nextReminderDate: Date?
    /// Klucze, które użytkownik właśnie cofnął w aplikacji. Bez tego najbliższa
    /// synchronizacja uznałaby wciąż odhaczone przypomnienie za świeżo zrobione.
    private var keysToReopen: Set<String> = []

    init(
        repository: PaymentRepository,
        notifications: NotificationService,
        reminders: RemindersService,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.notifications = notifications
        self.reminders = reminders
        self.calendar = calendar
    }

    var payments: [RecurringPayment] {
        snapshot.payments.sorted { lhs, rhs in
            if lhs.dueDay != rhs.dueDay { return lhs.dueDay < rhs.dueDay }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var entries: [PaymentEntry] {
        snapshot.entries
    }

    var currencyCode: String {
        snapshot.settings.currencyCode
    }

    var currentPeriod: MonthKey {
        MonthKey(date: Date(), calendar: calendar)
    }

    var medicationGroups: [MedicationGroup] {
        snapshot.medicationGroups.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var lessonPlans: [LessonPlan] {
        snapshot.lessonPlans.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func payments(of kind: LedgerKind) -> [RecurringPayment] {
        payments.filter { $0.kind == kind }
    }

    func activePayments(of kind: LedgerKind) -> [RecurringPayment] {
        payments(of: kind).filter(\.isActive)
    }

    func doses(in group: MedicationGroup) -> [MedicationDose] {
        snapshot.medicationDoses
            .filter { $0.groupID == group.id }
            .sorted { $0.time < $1.time }
    }

    func blocks(in plan: LessonPlan) -> [LessonBlock] {
        snapshot.lessonBlocks
            .filter { $0.planID == plan.id }
            .sorted {
                if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
                return $0.start < $1.start
            }
    }

    func bootstrap() async {
        reload()

        if !snapshot.settings.didSeedExamples && snapshot.payments.isEmpty {
            snapshot.payments = PaymentsSnapshot.exampleSeed()
            snapshot.settings.didSeedExamples = true
            persist()
        }

        authorizationStatus = await notifications.requestAuthorization()
        remindersAccessGranted = await reminders.requestAccess()
        remindersError = reminders.lastError
        await refreshReminders()
    }

    func reload() {
        do {
            snapshot = try repository.load()
            storageError = nil
        } catch {
            storageError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            snapshot = .empty
        }
    }

    func refreshAfterReturningToForeground() async {
        reload()
        authorizationStatus = await notifications.authorizationStatus()
        remindersAccessGranted = reminders.hasFullAccess()
        await refreshReminders()
    }

    func status(for payment: RecurringPayment, period: MonthKey) -> PaymentStatus {
        PaymentsEngine.status(
            for: payment,
            period: period,
            entries: snapshot.entries,
            now: Date(),
            calendar: calendar
        )
    }

    func entry(for payment: RecurringPayment, period: MonthKey) -> PaymentEntry? {
        PaymentsEngine.entry(
            paymentID: payment.id,
            period: period,
            entries: snapshot.entries
        )
    }

    func summary(for period: MonthKey, kind: LedgerKind) -> PeriodSummary {
        PaymentsEngine.summary(
            payments: snapshot.payments.filter { $0.kind == kind },
            period: period,
            entries: snapshot.entries
        )
    }

    func isChecked(itemID: UUID, key: String) -> Bool {
        snapshot.occurrenceChecks.contains { $0.itemID == itemID && $0.occurrenceKey == key }
    }

    func choreSlots(for chore: RecurringPayment) -> [ChoreSlot] {
        SystemReminderPlan.choreSlots(
            for: chore,
            now: Date(),
            calendar: calendar,
            lookaheadMonths: snapshot.settings.lookaheadMonths
        )
    }

    func isDoseChecked(_ dose: MedicationDose, on day: Date) -> Bool {
        isChecked(itemID: dose.id, key: DayKey(date: day, calendar: calendar).id)
    }

    func attentionCount() -> Int {
        let period = currentPeriod
        let today = calendar.startOfDay(for: Date())
        let money = snapshot.payments.filter { payment in
            payment.isActive
                && payment.kind != .chore
                && !PaymentsEngine.isPaid(
                    paymentID: payment.id,
                    period: period,
                    entries: snapshot.entries
                )
        }.count

        let chores = snapshot.payments
            .filter { $0.isActive && $0.kind == .chore }
            .reduce(into: 0) { count, chore in
                count += choreSlots(for: chore).filter { slot in
                    calendar.startOfDay(for: slot.due) <= today
                        && !isChecked(itemID: chore.id, key: slot.key)
                }.count
            }

        let dayID = DayKey(date: Date(), calendar: calendar).id
        let doses = snapshot.medicationDoses.filter { dose in
            dose.isActive && !isChecked(itemID: dose.id, key: dayID)
        }.count

        return money + chores + doses
    }

    func addPayment(_ payment: RecurringPayment) {
        snapshot.payments.append(payment)
        persist()
        Task { await refreshReminders() }
    }

    func updatePayment(_ payment: RecurringPayment) {
        guard let index = snapshot.payments.firstIndex(where: { $0.id == payment.id }) else {
            return
        }
        snapshot.payments[index] = payment
        persist()
        Task { await refreshReminders() }
    }

    func deletePayment(_ payment: RecurringPayment) {
        snapshot.payments.removeAll { $0.id == payment.id }
        snapshot.occurrenceChecks.removeAll { $0.itemID == payment.id }
        persist()
        Task { await refreshReminders() }
    }

    func markPaid(
        _ payment: RecurringPayment,
        period: MonthKey,
        coversDate: Date? = nil,
        at date: Date = Date()
    ) {
        recordPaid(paymentID: payment.id, period: period, at: date, coversDate: coversDate)
    }

    func markPaid(paymentID: UUID, period: MonthKey, at date: Date = Date()) {
        recordPaid(paymentID: paymentID, period: period, at: date, coversDate: nil)
    }

    func markUnpaid(_ payment: RecurringPayment, period: MonthKey) {
        keysToReopen.insert(ReminderLink.payment(id: payment.id, period: period))
        snapshot.entries.removeAll { $0.paymentID == payment.id && $0.period == period }
        persist()
        Task { await refreshReminders() }
    }

    func completeOccurrence(itemID: UUID, key: String, coversDate: Date, reopenKey: String) {
        guard !isChecked(itemID: itemID, key: key) else { return }
        keysToReopen.remove(reopenKey)
        snapshot.occurrenceChecks.append(
            OccurrenceCheck(itemID: itemID, occurrenceKey: key, coversDate: coversDate)
        )
        persist()
        Task { await refreshReminders() }
    }

    func undoOccurrence(itemID: UUID, key: String, reopenKey: String) {
        keysToReopen.insert(reopenKey)
        snapshot.occurrenceChecks.removeAll { $0.itemID == itemID && $0.occurrenceKey == key }
        persist()
        Task { await refreshReminders() }
    }

    func addMedicationGroup(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        snapshot.medicationGroups.append(MedicationGroup(name: trimmed))
        persist()
        Task { await refreshReminders() }
    }

    func renameMedicationGroup(_ group: MedicationGroup, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = snapshot.medicationGroups.firstIndex(where: { $0.id == group.id })
        else { return }
        snapshot.medicationGroups[index].name = trimmed
        persist()
        Task { await refreshReminders() }
    }

    func deleteMedicationGroup(_ group: MedicationGroup) {
        let doseIDs = Set(snapshot.medicationDoses.filter { $0.groupID == group.id }.map(\.id))
        snapshot.medicationGroups.removeAll { $0.id == group.id }
        snapshot.medicationDoses.removeAll { $0.groupID == group.id }
        snapshot.occurrenceChecks.removeAll { doseIDs.contains($0.itemID) }
        persist()
        Task { await refreshReminders() }
    }

    func addDose(groupID: UUID, name: String, time: TimeOfDay) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        snapshot.medicationDoses.append(
            MedicationDose(groupID: groupID, name: trimmed, time: time)
        )
        persist()
        Task { await refreshReminders() }
    }

    func updateDose(_ dose: MedicationDose) {
        guard let index = snapshot.medicationDoses.firstIndex(where: { $0.id == dose.id }) else {
            return
        }
        snapshot.medicationDoses[index] = dose
        persist()
        Task { await refreshReminders() }
    }

    func deleteDose(_ dose: MedicationDose) {
        snapshot.medicationDoses.removeAll { $0.id == dose.id }
        snapshot.occurrenceChecks.removeAll { $0.itemID == dose.id }
        persist()
        Task { await refreshReminders() }
    }

    func setDose(_ dose: MedicationDose, on day: Date, done: Bool) {
        let key = DayKey(date: day, calendar: calendar).id
        let reopenKey = ReminderLink.dose(id: dose.id, day: key)
        if done {
            let covers = DayKey(date: day, calendar: calendar).date(time: dose.time, calendar: calendar) ?? day
            completeOccurrence(itemID: dose.id, key: key, coversDate: covers, reopenKey: reopenKey)
        } else {
            undoOccurrence(itemID: dose.id, key: key, reopenKey: reopenKey)
        }
    }

    func addLessonPlan(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        snapshot.lessonPlans.append(LessonPlan(name: trimmed))
        persist()
        Task { await refreshReminders() }
    }

    func renameLessonPlan(_ plan: LessonPlan, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = snapshot.lessonPlans.firstIndex(where: { $0.id == plan.id })
        else { return }
        snapshot.lessonPlans[index].name = trimmed
        persist()
        Task { await refreshReminders() }
    }

    func deleteLessonPlan(_ plan: LessonPlan) {
        snapshot.lessonPlans.removeAll { $0.id == plan.id }
        snapshot.lessonBlocks.removeAll { $0.planID == plan.id }
        persist()
        Task { await refreshReminders() }
    }

    func saveLessonBlock(_ block: LessonBlock) {
        if let index = snapshot.lessonBlocks.firstIndex(where: { $0.id == block.id }) {
            snapshot.lessonBlocks[index] = block
        } else {
            snapshot.lessonBlocks.append(block)
        }
        persist()
        Task { await refreshReminders() }
    }

    func deleteLessonBlock(_ block: LessonBlock) {
        snapshot.lessonBlocks.removeAll { $0.id == block.id }
        persist()
        Task { await refreshReminders() }
    }

    func refreshReminders() async {
        await notifications.retireScheduledReminders()
        remindersAccessGranted = reminders.hasFullAccess()
        guard remindersAccessGranted == true else {
            remindersError = "Brak dostępu do Przypomnień."
            scheduledReminderCount = 0
            nextReminderDate = nil
            await notifications.setBadge(attentionCount())
            return
        }

        let blueprint = systemBlueprint()
        let report = await reminders.synchronize(
            drafts: blueprint.open,
            doneKeys: blueprint.doneKeys,
            reopenKeys: keysToReopen
        )
        if let errorMessage = report.errorMessage {
            remindersError = errorMessage
            await notifications.setBadge(attentionCount())
            return
        }

        keysToReopen.subtract(report.reopenedKeys)
        remindersError = nil

        if importCompletions(report.externallyCompletedKeys) {
            let second = systemBlueprint()
            let followUp = await reminders.synchronize(
                drafts: second.open,
                doneKeys: second.doneKeys,
                reopenKeys: []
            )
            scheduledReminderCount = followUp.errorMessage == nil ? followUp.openCount : second.open.count
            nextReminderDate = followUp.nextAlarm
            remindersError = followUp.errorMessage
        } else {
            scheduledReminderCount = report.openCount
            nextReminderDate = report.nextAlarm
        }

        await notifications.setBadge(attentionCount())
    }

    func requestAuthorization() async {
        authorizationStatus = await notifications.requestAuthorization()
        remindersAccessGranted = await reminders.requestAccess()
        remindersError = reminders.lastError
        await refreshReminders()
    }

    func sendTestReminder() async {
        remindersError = await reminders.addTestReminder()
        remindersAccessGranted = reminders.hasFullAccess()
    }

    func snooze(paymentID: UUID, period: MonthKey, title: String, body: String) async {
        await notifications.scheduleSnooze(
            paymentID: paymentID,
            period: period,
            title: title,
            body: body,
            badge: attentionCount()
        )
    }

    private func systemBlueprint() -> SystemReminderBlueprint {
        SystemReminderPlan.make(
            SystemReminderPlan.Context(
                payments: snapshot.payments,
                entries: snapshot.entries,
                checks: snapshot.occurrenceChecks,
                groups: snapshot.medicationGroups,
                doses: snapshot.medicationDoses,
                plans: snapshot.lessonPlans,
                blocks: snapshot.lessonBlocks,
                now: Date(),
                calendar: calendar,
                lookaheadMonths: snapshot.settings.lookaheadMonths,
                currencyCode: snapshot.settings.currencyCode
            )
        )
    }

    private func recordPaid(
        paymentID: UUID,
        period: MonthKey,
        at date: Date,
        coversDate: Date?
    ) {
        guard writePaid(paymentID: paymentID, period: period, at: date, coversDate: coversDate) else {
            return
        }
        persist()
        Task { await refreshReminders() }
    }

    private func writePaid(
        paymentID: UUID,
        period: MonthKey,
        at date: Date,
        coversDate explicitCovers: Date?
    ) -> Bool {
        guard let payment = snapshot.payments.first(where: { $0.id == paymentID }) else {
            return false
        }
        let covers = explicitCovers
            ?? period.date(day: payment.dueDay, time: payment.effectiveTimes[0], calendar: calendar)
            ?? date

        if let index = snapshot.entries.firstIndex(where: {
            $0.paymentID == paymentID && $0.period == period
        }) {
            snapshot.entries[index].paidAt = date
            snapshot.entries[index].coversDate = covers
            snapshot.entries[index].amountPaid = payment.amount
            snapshot.entries[index].paymentName = payment.name
            snapshot.entries[index].kind = payment.kind
            return true
        }

        snapshot.entries.append(
            PaymentEntry(
                paymentID: paymentID,
                period: period,
                paidAt: date,
                amountPaid: payment.amount,
                paymentName: payment.name,
                coversDate: covers,
                kind: payment.kind
            )
        )
        return true
    }

    private func importCompletions(_ keys: [String]) -> Bool {
        var changed = false
        for key in keys where applyImported(key) {
            changed = true
        }
        if changed {
            persist()
        }
        return changed
    }

    private func applyImported(_ key: String) -> Bool {
        let parts = key.split(separator: "/").map(String.init)
        guard parts.count == 3 else { return false }

        switch parts[0] {
        case "pay":
            guard let id = UUID(uuidString: parts[1]),
                  let period = MonthKey(parsing: parts[2]),
                  !PaymentsEngine.isPaid(paymentID: id, period: period, entries: snapshot.entries)
            else { return false }
            return writePaid(paymentID: id, period: period, at: Date(), coversDate: nil)

        case "chore":
            guard let id = UUID(uuidString: parts[1]) else { return false }
            let occurrence = parts[2]
            guard !isChecked(itemID: id, key: occurrence) else { return false }
            let covers = coversDate(forChoreID: id, occurrence: occurrence) ?? Date()
            snapshot.occurrenceChecks.append(
                OccurrenceCheck(itemID: id, occurrenceKey: occurrence, coversDate: covers)
            )
            return true

        case "dose":
            guard let id = UUID(uuidString: parts[1]) else { return false }
            let day = parts[2]
            guard !isChecked(itemID: id, key: day) else { return false }
            let covers = DayKey(parsing: day)?.startOfDay(calendar: calendar) ?? Date()
            snapshot.occurrenceChecks.append(
                OccurrenceCheck(itemID: id, occurrenceKey: day, coversDate: covers)
            )
            return true

        default:
            return false
        }
    }

    private func coversDate(forChoreID id: UUID, occurrence: String) -> Date? {
        let chore = snapshot.payments.first { $0.id == id }
        let time = chore?.effectiveTimes[0] ?? .morning
        if let day = DayKey(parsing: occurrence) {
            return day.date(time: time, calendar: calendar)
        }
        if let period = MonthKey(parsing: occurrence) {
            return period.date(day: chore?.dueDay ?? 1, time: time, calendar: calendar)
        }
        return nil
    }

    private func persist() {
        do {
            try repository.save(snapshot)
            storageError = nil
        } catch {
            storageError = "Nie udało się zapisać danych: \(error.localizedDescription)"
        }
    }
}
