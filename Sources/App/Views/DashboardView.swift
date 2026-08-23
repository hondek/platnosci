import SwiftUI

/// Cel arkusza edycji. Osobny typ, bo `sheet(item:)` potrzebuje `Identifiable`,
/// a chcemy jednym mechanizmem obsłużyć i dodawanie, i edycję.
enum PaymentEditorTarget: Identifiable {
    case new
    case existing(RecurringPayment)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let payment): return payment.id.uuidString
        }
    }
}

struct DashboardView: View {
    @Environment(PaymentStore.self) private var store

    @State private var period = MonthKey(date: Date(), calendar: .current)
    @State private var editorTarget: PaymentEditorTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let storageError = store.storageError {
                        WarningBanner(
                            icon: "exclamationmark.triangle.fill",
                            tint: .red,
                            message: storageError
                        )
                    }

                    if store.authorizationStatus == .denied {
                        WarningBanner(
                            icon: "bell.slash.fill",
                            tint: .orange,
                            message: "Powiadomienia są wyłączone w Ustawieniach iOS. Bez nich przypomnienia nie zadziałają — zostanie tylko plakietka na ikonie."
                        )
                    }

                    monthSwitcher
                    SummaryCard(summary: store.summary(for: period), currencyCode: store.currencyCode)

                    if store.activePayments.isEmpty {
                        ContentUnavailableView(
                            "Brak płatności",
                            systemImage: "creditcard",
                            description: Text("Dodaj pierwszą stałą płatność przyciskiem plus.")
                        )
                        .padding(.top, 32)
                    } else {
                        ForEach(store.activePayments) { payment in
                            PaymentCardView(
                                payment: payment,
                                status: store.status(for: payment, period: period),
                                currencyCode: store.currencyCode,
                                onMarkPaid: { store.markPaid(payment, period: period) },
                                onMarkUnpaid: { store.markUnpaid(payment, period: period) },
                                onEdit: { editorTarget = .existing(payment) }
                            )
                        }
                    }

                    reminderFooter
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Płatności")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("Historia", systemImage: "clock.arrow.circlepath")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Ustawienia", systemImage: "gearshape")
                    }

                    Button {
                        editorTarget = .new
                    } label: {
                        Label("Dodaj", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                switch target {
                case .new:
                    PaymentEditorView(payment: nil)
                case .existing(let payment):
                    PaymentEditorView(payment: payment)
                }
            }
        }
    }

    private var monthSwitcher: some View {
        HStack {
            Button {
                period = period.adding(months: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Poprzedni miesiąc")

            Spacer()

            VStack(spacing: 2) {
                Text(period.displayName(calendar: .current))
                    .font(.title2.bold())

                if period != store.currentPeriod {
                    Button("Wróć do bieżącego") {
                        period = store.currentPeriod
                    }
                    .font(.caption)
                }
            }

            Spacer()

            Button {
                period = period.adding(months: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Następny miesiąc")
        }
    }

    /// Podgląd tego, co faktycznie siedzi w systemie. Dzięki temu widać na oczy,
    /// że przypomnienia są uzbrojone, zamiast wierzyć na słowo.
    private var reminderFooter: some View {
        VStack(spacing: 4) {
            Text("Uzbrojonych przypomnień: \(store.scheduledReminderCount)")
            if let next = store.nextReminderDate {
                Text("Najbliższe: \(next.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }
}

private struct SummaryCard: View {
    let summary: PeriodSummary
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Podsumowanie miesiąca")
                    .font(.headline)
                Spacer()
                if summary.isComplete {
                    Label("Wszystko opłacone", systemImage: "checkmark.seal.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(summary.paid.formatted(currencyCode: currencyCode))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("z \(summary.total.formatted(currencyCode: currencyCode))")
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: summary.progress)
                .tint(summary.isComplete ? .green : .accentColor)

            HStack {
                Text("\(summary.paidCount) z \(summary.totalCount) opłaconych")
                Spacer()
                if !summary.remaining.isZero {
                    Text("zostało \(summary.remaining.formatted(currencyCode: currencyCode))")
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct WarningBanner: View {
    let icon: String
    let tint: Color
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding()
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
