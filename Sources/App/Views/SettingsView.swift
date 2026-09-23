import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(PaymentStore.self) private var store

    @State private var editorTarget: PaymentEditorTarget?
    @State private var testSent = false

    var body: some View {
        List {
            paymentsSection
            notificationsSection
            diagnosticsSection
            explanationSection
        }
        .navigationTitle("Ustawienia")
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new:
                PaymentEditorView(payment: nil, kind: .outgoing)
            case .existing(let payment):
                PaymentEditorView(payment: payment, kind: payment.kind)
            }
        }
    }

    private var paymentsSection: some View {
        Section {
            ForEach(store.payments) { payment in
                Button {
                    editorTarget = .existing(payment)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(payment.name)
                                .foregroundStyle(.primary)
                            Text(payment.amount.isZero ? payment.kind.boardTitle : payment.amount.formatted(currencyCode: store.currencyCode))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(scheduleLabel(payment)), \(payment.effectiveTimes.map(\.formatted).joined(separator: ", "))")
                            if !payment.isActive {
                                Text("wyłączona")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Pozycje")
        } footer: {
            Text("Dotknij, żeby edytować. Wyłączenie płatności kasuje jej zaplanowane przypomnienia.")
        }
    }

    private var notificationsSection: some View {
        Section {
            HStack {
                Text("Dostęp do Przypomnień")
                Spacer()
                Text(remindersAccessLabel)
                    .foregroundStyle(store.remindersAccessGranted == true ? .green : .orange)
            }

            if store.remindersAccessGranted != true {
                Button("Poproś o dostęp") {
                    Task { await store.requestAuthorization() }
                }
            }

            if store.remindersAccessGranted == false,
               let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link("Otwórz Ustawienia iOS", destination: settingsURL)
            }

            Button {
                Task {
                    await store.sendTestReminder()
                    testSent = true
                }
            } label: {
                Label("Dodaj testowe przypomnienie", systemImage: "checklist")
            }

            if testSent {
                Text("Za minutę pojawi się na liście Płatności w aplikacji Przypomnienia.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Przypomnienia")
        }
    }

    /// Pokazuje stan faktyczny, nie deklarowany. Przy limicie 64 oczekujących
    /// powiadomień na aplikację warto widzieć, ile ich naprawdę jest.
    private var diagnosticsSection: some View {
        Section {
            LabeledContent("Wpisów w Przypomnieniach", value: "\(store.scheduledReminderCount)")

            if let next = store.nextReminderDate {
                LabeledContent(
                    "Najbliższe",
                    value: next.formatted(date: .abbreviated, time: .shortened)
                )
            }

            LabeledContent(
                "Otwarte w tym miesiącu",
                value: "\(store.attentionCount())"
            )

            LabeledContent(
                "Dane widgetu",
                value: StorageLocation.isUsingSharedContainer ? "kontener wspólny" : "tylko aplikacja"
            )

            Button("Przelicz przypomnienia teraz") {
                Task { await store.refreshReminders() }
            }
        } header: {
            Text("Diagnostyka")
        } footer: {
            Text("Plan jest przeliczany przy każdym otwarciu aplikacji, po każdej zmianie i okresowo w tle.")
        }
    }

    private var explanationSection: some View {
        Section {
            Text("Każdy termin staje się wpisem w aplikacji Przypomnienia i zostaje tam, dopóki go nie odhaczysz — w tej aplikacji albo bezpośrednio w Przypomnieniach.")
                .font(.footnote)

            VStack(alignment: .leading, spacing: 8) {
                bullet("Płatności, należności i zwykłe przypomnienia mają osobne listy.")
                bullet("Godziny ustawiasz sam. Każda godzina to osobny alarm tego samego wpisu.")
                bullet("Leki (np. grupa LEKARSTWA) odhaczasz codziennie, każdą dawkę o swojej godzinie.")
                bullet("Plan lekcji, na przykład „Plan lekcji Róża”, dostaje przypomnienie o godzinie rozpoczęcia bloku.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("Jak działa przypominanie")
        }
    }

    private var remindersAccessLabel: String {
        switch store.remindersAccessGranted {
        case .some(true): return "udzielony"
        case .some(false): return "brak"
        case .none: return "sprawdzanie"
        }
    }

    private func scheduleLabel(_ payment: RecurringPayment) -> String {
        if payment.kind == .chore, payment.cadence == .weekly {
            return BoardNaming.weekdayName(payment.weekday ?? 2)
        }
        return "\(payment.dueDay). dnia"
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
