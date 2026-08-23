import SwiftUI

struct PaymentEditorView: View {
    /// `nil` oznacza nową płatność.
    let payment: RecurringPayment?

    @Environment(PaymentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var amount: Decimal
    @State private var note: String
    @State private var dueDay: Int
    @State private var reminderDate: Date
    @State private var intensity: ReminderIntensity
    @State private var isActive: Bool
    @State private var showDeleteConfirmation = false

    @FocusState private var amountFieldFocused: Bool

    init(payment: RecurringPayment?) {
        self.payment = payment
        _name = State(initialValue: payment?.name ?? "")
        _amount = State(initialValue: payment?.amount.value ?? 0)
        _note = State(initialValue: payment?.note ?? "")
        _dueDay = State(initialValue: payment?.dueDay ?? 10)
        _intensity = State(initialValue: payment?.intensity ?? .persistent)
        _isActive = State(initialValue: payment?.isActive ?? true)

        let time = payment?.reminderTime ?? .morning
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        _reminderDate = State(
            initialValue: Calendar.current.date(from: components) ?? Date()
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Płatność") {
                    TextField("Nazwa, np. Marek", text: $name)
                        .textInputAutocapitalization(.words)

                    HStack {
                        Text("Kwota")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($amountFieldFocused)
                        Text(store.currencyCode)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Notatka (opcjonalnie)", text: $note, axis: .vertical)

                    Toggle("Aktywna", isOn: $isActive)
                }

                Section {
                    Picker("Dzień miesiąca", selection: $dueDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }

                    DatePicker(
                        "Godzina",
                        selection: $reminderDate,
                        displayedComponents: .hourAndMinute
                    )
                } header: {
                    Text("Termin")
                } footer: {
                    Text("Dni 29–31 są automatycznie przycinane do ostatniego dnia krótszego miesiąca.")
                }

                Section {
                    Picker("Tryb", selection: $intensity) {
                        ForEach(ReminderIntensity.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Natarczywość przypomnień")
                } footer: {
                    Text(intensity.explanation)
                }

                if payment != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Usuń płatność", systemImage: "trash")
                        }
                    } footer: {
                        Text("Historia wpłat zostanie zachowana.")
                    }
                }
            }
            .navigationTitle(payment == nil ? "Nowa płatność" : "Edytuj płatność")
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
                "Usunąć tę płatność?",
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

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && amount > 0
    }

    private func save() {
        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: reminderDate
        )
        let time = TimeOfDay(
            hour: components.hour ?? 9,
            minute: components.minute ?? 0
        )

        if var existing = payment {
            existing.name = trimmedName
            existing.amount = Money(value: amount)
            existing.note = note
            existing.dueDay = dueDay
            existing.reminderTime = time
            existing.intensity = intensity
            existing.isActive = isActive
            store.updatePayment(existing)
        } else {
            store.addPayment(
                RecurringPayment(
                    name: trimmedName,
                    amount: Money(value: amount),
                    note: note,
                    dueDay: dueDay,
                    reminderTime: time,
                    intensity: intensity,
                    isActive: isActive
                )
            )
        }

        dismiss()
    }
}
