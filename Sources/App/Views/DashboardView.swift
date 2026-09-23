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

private struct PendingMark: Identifiable {
    let payment: RecurringPayment
    let period: MonthKey
    let suggested: Date

    var id: String { "\(payment.id.uuidString)-\(period.id)" }
}

struct DashboardView: View {
    @Environment(PaymentStore.self) private var store
    let kind: LedgerKind

    @State private var period = MonthKey(date: Date(), calendar: .current)
    @State private var editorTarget: PaymentEditorTarget?
    @State private var pendingMark: PendingMark?

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

                    if store.remindersAccessGranted == false {
                        WarningBanner(
                            icon: "checklist",
                            tint: .orange,
                            message: "Brak dostępu do Przypomnień. Terminy nie trafią do systemowej aplikacji, dopóki nie przyznasz zgody."
                        )
                    }

                    monthSwitcher
                    SummaryCard(
                        summary: store.summary(for: period, kind: kind),
                        currencyCode: store.currencyCode,
                        kind: kind
                    )

                    if store.activePayments(of: kind).isEmpty {
                        ContentUnavailableView(
                            "Brak pozycji",
                            systemImage: kind == .incoming ? "arrow.down.circle" : "creditcard",
                            description: Text(emptyDescription)
                        )
                        .padding(.top, 32)
                    } else {
                        ForEach(store.activePayments(of: kind)) { payment in
                            PaymentCardView(
                                payment: payment,
                                status: store.status(for: payment, period: period),
                                coversDate: store.entry(for: payment, period: period)?.coversDate,
                                currencyCode: store.currencyCode,
                                onMarkPaid: { beginMark(payment) },
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
            .navigationTitle(kind.boardTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        HistoryView(kind: kind)
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
                    PaymentEditorView(payment: nil, kind: kind)
                case .existing(let payment):
                    PaymentEditorView(payment: payment, kind: payment.kind)
                }
            }
            .sheet(item: $pendingMark) { pending in
                CoversDateSheet(
                    title: "Za kiedy?",
                    message: "Data, której dotyczy ta pozycja. Osobno od chwili odhaczenia.",
                    confirmTitle: pending.payment.kind.doneButton,
                    date: pending.suggested
                ) { date in
                    store.markPaid(pending.payment, period: pending.period, coversDate: date)
                }
            }
        }
    }

    private var emptyDescription: String {
        switch kind {
        case .outgoing: return "Dodaj pierwszą stałą płatność przyciskiem plus."
        case .incoming: return "Dodaj osobę, która ma Ci oddać pieniądze."
        case .chore: return "Dodaj przypomnienie, na przykład wystawienie kosza."
        }
    }

    private func beginMark(_ payment: RecurringPayment) {
        let suggested = period.date(
            day: payment.dueDay,
            time: payment.effectiveTimes[0],
            calendar: .current
        ) ?? Date()
        pendingMark = PendingMark(payment: payment, period: period, suggested: suggested)
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

    private var reminderFooter: some View {
        VStack(spacing: 4) {
            Text("Wpisów w Przypomnieniach: \(store.scheduledReminderCount)")
            if let next = store.nextReminderDate {
                Text("Najbliższy alarm: \(next.formatted(date: .abbreviated, time: .shortened))")
            }
            if let remindersError = store.remindersError {
                Text(remindersError)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.top, 8)
    }
}

private struct SummaryCard: View {
    let summary: PeriodSummary
    let currencyCode: String
    let kind: LedgerKind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind.summaryTitle)
                    .font(.headline)
                Spacer()
                if summary.isComplete {
                    Label(kind.completeLabel, systemImage: "checkmark.seal.fill")
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
                Text("\(summary.paidCount) z \(summary.totalCount) \(kind.progressNoun)")
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
