import SwiftUI

struct PaymentEditorView: View {
    /// `nil` oznacza nową pozycję.
    let payment: RecurringPayment?
    let kind: LedgerKind

    @Environment(PaymentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var amountText: String
    @State private var note: String
    @State private var dueDay: Int
    @State private var cadence: ItemCadence
    @State private var weekday: Int
    @State private var timeRows: [TimeRow]
    @State private var isActive: Bool
    @State private var showDeleteConfirmation = false

    @FocusState private var amountFieldFocused: Bool

    init(payment: RecurringPayment?, kind: LedgerKind) {
        self.payment = payment
        self.kind = payment?.kind ?? kind
        _name = State(initialValue: payment?.name ?? "")
        _note = State(initialValue: payment?.note ?? "")
        _dueDay = State(initialValue: payment?.dueDay ?? 10)
        _cadence = State(initialValue: payment?.cadence ?? .monthly)
        _weekday = State(initialValue: payment?.weekday ?? 2)
        _isActive = State(initialValue: payment?.isActive ?? true)

        let resolvedKind = payment?.kind ?? kind
        if let payment, resolvedKind.handlesMoney, !payment.amount.isZero {
            _amountText = State(initialValue: Self.amountText(from: payment.amount))
        } else {
            _amountText = State(initialValue: "")
        }

        let times = payment?.effectiveTimes ?? [.morning]
        _timeRows = State(initialValue: times.map { TimeRow(time: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(kind.handlesMoney ? "Płatność" : "Przypomnienie") {
                    TextField(namePrompt, text: $name)
                        .textInputAutocapitalization(.words)

                    if kind.handlesMoney {
                        HStack {
                            Text("Kwota")
                            Spacer()
                            TextField("wpisz kwotę", text: $amountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($amountFieldFocused)
                            Text(store.currencyCode)
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("Notatka (opcjonalnie)", text: $note, axis: .vertical)
                    Toggle("Aktywna", isOn: $isActive)
                }

                if kind == .chore {
                    Section("Powtarzanie") {
                        Picker("Rytm", selection: $cadence) {
                            ForEach(ItemCadence.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    }
                }

                Section {
                    if kind != .chore || cadence == .monthly {
                        Picker("Dzień miesiąca", selection: $dueDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text("\(day)").tag(day)
                            }
                        }
                    } else {
                        Picker("Dzień tygodnia", selection: $weekday) {
                            ForEach(BoardNaming.orderedWeekdays(), id: \.self) { day in
                                Text(BoardNaming.weekdayName(day)).tag(day)
                            }
                        }
                    }
                } header: {
                    Text("Termin")
                } footer: {
                    if kind != .chore || cadence == .monthly {
                        Text("Dni 29–31 są automatycznie przycinane do ostatniego dnia krótszego miesiąca.")
                    }
                }

                Section {
                    ForEach($timeRows) { $row in
                        DatePicker(
                            "Godzina",
                            selection: $row.date,
                            displayedComponents: .hourAndMinute
                        )
                    }
                    .onDelete(perform: deleteTimes)

                    Button("Dodaj godzinę", systemImage: "plus") {
                        timeRows.append(TimeRow(date: nextTime()))
                    }
                } header: {
                    Text("Godziny przypomnień")
                } footer: {
                    Text("Każda godzina to osobny alarm wpisu w aplikacji Przypomnienia. Wpis zostaje na liście, dopóki go nie odhaczysz.")
                }

                if payment != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(deleteTitle, systemImage: "trash")
                        }
                    } footer: {
                        if kind.handlesMoney {
                            Text("Historia wpłat zostanie zachowana.")
                        }
                    }
                }
            }
            .navigationTitle(payment == nil ? kind.newItemTitle : kind.editItemTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz", action: save)
                        .disabled(!isValid)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Gotowe") { amountFieldFocused = false }
                }
            }
            .confirmationDialog(
                deleteTitle + "?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Usuń", role: .destructive) {
                    if let payment {
                        store.deletePayment(payment)
                    }
                    dismiss()
                }
                Button("Anuluj", role: .cancel) {}
            }
        }
    }

    private var namePrompt: String {
        switch kind {
        case .outgoing: return "Nazwa, np. czynsz"
        case .incoming: return "Kto, np. Marek"
        case .chore: return "Nazwa, np. wystawienie kosza"
        }
    }

    private var deleteTitle: String {
        switch kind {
        case .outgoing: return "Usuń płatność"
        case .incoming: return "Usuń należność"
        case .chore: return "Usuń przypomnienie"
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedAmount: Decimal? {
        Self.parseAmount(amountText)
    }

    private var isValid: Bool {
        guard !trimmedName.isEmpty, !timeRows.isEmpty else { return false }
        guard kind.handlesMoney else { return true }
        guard let parsedAmount else { return false }
        return parsedAmount > 0
    }

    private func deleteTimes(at offsets: IndexSet) {
        guard timeRows.count - offsets.count >= 1 else { return }
        timeRows.remove(atOffsets: offsets)
    }

    private func nextTime() -> Date {
        let calendar = Calendar.current
        let base = timeRows.last?.date ?? Date()
        return calendar.date(byAdding: .hour, value: 4, to: base) ?? base
    }

    private func save() {
        let times = uniqueTimes()
        let amount = kind.handlesMoney ? Money(value: parsedAmount ?? 0) : .zero

        if var existing = payment {
            existing.name = trimmedName
            existing.amount = amount
            existing.note = note
            existing.dueDay = dueDay
            existing.reminderTimes = times
            existing.reminderTime = times[0]
            existing.cadence = kind == .chore ? cadence : .monthly
            existing.weekday = kind == .chore && cadence == .weekly ? weekday : nil
            existing.isActive = isActive
            existing.kind = kind
            store.updatePayment(existing)
        } else {
            store.addPayment(
                RecurringPayment(
                    name: trimmedName,
                    amount: amount,
                    note: note,
                    dueDay: dueDay,
                    reminderTime: times[0],
                    isActive: isActive,
                    kind: kind,
                    cadence: kind == .chore ? cadence : .monthly,
                    weekday: kind == .chore && cadence == .weekly ? weekday : nil,
                    reminderTimes: times
                )
            )
        }

        dismiss()
    }

    private func uniqueTimes() -> [TimeOfDay] {
        let calendar = Calendar.current
        let times = timeRows.map { row -> TimeOfDay in
            let parts = calendar.dateComponents([.hour, .minute], from: row.date)
            return TimeOfDay(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        }
        var seen: Set<Int> = []
        let unique = times.filter { seen.insert($0.hour * 60 + $0.minute).inserted }
        return unique.isEmpty ? [.morning] : unique.sorted()
    }

    private static func amountText(from money: Money) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: money.value as NSDecimalNumber) ?? ""
    }

    private static func parseAmount(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: trimmed) {
            return number.decimalValue
        }

        return Decimal(string: trimmed.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
    }
}

private struct TimeRow: Identifiable {
    let id = UUID()
    var date: Date

    init(date: Date) {
        self.date = date
    }

    init(time: TimeOfDay) {
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        date = Calendar.current.date(from: components) ?? Date()
    }
}
