import SwiftUI

/// Historia liczona z zapisanych wpłat, a nie z aktualnych ustawień płatności.
/// Każdy wpis nosi własną kopię kwoty i nazwy, więc podniesienie kwoty dzisiaj
/// nie przepisuje tego, co zapłaciłeś rok temu.
struct HistoryView: View {
    @Environment(PaymentStore.self) private var store

    private let monthsBack = 36

    var body: some View {
        List {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "Brak historii",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Oznacz pierwszą płatność jako zapłaconą.")
                )
            } else {
                ForEach(periodsWithEntries, id: \.self) { period in
                    Section(period.displayName(calendar: .current)) {
                        ForEach(entries(in: period)) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.paymentName.isEmpty ? "Płatność" : entry.paymentName)
                                        .font(.body)
                                    Text(entry.paidAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(entry.amountPaid.formatted(currencyCode: store.currencyCode))
                                    .font(.body.monospacedDigit())
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Historia")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    YearlyTotalsView()
                } label: {
                    Label("Podsumowania", systemImage: "chart.bar")
                }
            }
        }
    }

    /// Pokazujemy tylko miesiące, w których coś się zdarzyło — pusta lista 36
    /// wierszy „Brak" niczego nie wnosi.
    private var periodsWithEntries: [MonthKey] {
        let window = Set(
            PaymentsEngine.historyPeriods(
                from: Date(),
                calendar: .current,
                count: monthsBack
            )
        )
        return Set(store.entries.map(\.period))
            .intersection(window)
            .sorted(by: >)
    }

    private func entries(in period: MonthKey) -> [PaymentEntry] {
        store.entries
            .filter { $0.period == period }
            .sorted { $0.paidAt < $1.paidAt }
    }
}

private struct YearlyTotalsView: View {
    @Environment(PaymentStore.self) private var store

    var body: some View {
        List {
            ForEach(years, id: \.self) { year in
                HStack {
                    Text(String(year))
                    Spacer()
                    Text(
                        PaymentsEngine
                            .yearlyTotal(year: year, entries: store.entries)
                            .formatted(currencyCode: store.currencyCode)
                    )
                    .font(.body.monospacedDigit().bold())
                }
            }
        }
        .navigationTitle("Suma po latach")
    }

    private var years: [Int] {
        Set(store.entries.map(\.period.year)).sorted(by: >)
    }
}
