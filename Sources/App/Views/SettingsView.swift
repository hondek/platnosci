import SwiftUI
import UIKit
import UserNotifications

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
                PaymentEditorView(payment: nil)
            case .existing(let payment):
                PaymentEditorView(payment: payment)
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
                            Text(payment.amount.formatted(currencyCode: store.currencyCode))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(payment.dueDay). dnia, \(payment.reminderTime.formatted)")
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
            Text("Stałe płatności")
        } footer: {
            Text("Dotknij, żeby edytować. Wyłączenie płatności kasuje jej zaplanowane przypomnienia.")
        }
    }

    private var notificationsSection: some View {
        Section {
            HStack {
                Text("Zgoda na powiadomienia")
                Spacer()
                Text(authorizationLabel)
                    .foregroundStyle(authorizationColor)
            }

            if store.authorizationStatus == .notDetermined {
                Button("Poproś o zgodę") {
                    Task { await store.requestAuthorization() }
                }
            }

            if store.authorizationStatus == .denied,
               let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link("Otwórz Ustawienia iOS", destination: settingsURL)
            }

            Button {
                Task {
                    await store.sendTestNotification()
                    testSent = true
                }
            } label: {
                Label("Wyślij powiadomienie testowe", systemImage: "bell.badge")
            }

            if testSent {
                Text("Powiadomienie przyjdzie w ciągu 15 sekund.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Powiadomienia")
        }
    }

    /// Pokazuje stan faktyczny, nie deklarowany. Przy limicie 64 oczekujących
    /// powiadomień na aplikację warto widzieć, ile ich naprawdę jest.
    private var diagnosticsSection: some View {
        Section {
            LabeledContent("Uzbrojonych przypomnień", value: "\(store.scheduledReminderCount)")
            LabeledContent(
                "Limit systemowy iOS",
                value: "\(ReminderPlanner.budget) z 64"
            )

            if let next = store.nextReminderDate {
                LabeledContent(
                    "Najbliższe",
                    value: next.formatted(date: .abbreviated, time: .shortened)
                )
            }

            LabeledContent(
                "Niezapłacone w tym miesiącu",
                value: "\(store.unpaidCountForCurrentPeriod())"
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
            Text("iOS nie pozwala przykleić powiadomienia do ekranu na stałe — taki mechanizm w ogóle nie istnieje w systemie. Dlatego przypomnienie działa trzema warstwami:")
                .font(.footnote)

            VStack(alignment: .leading, spacing: 8) {
                bullet("Plakietka na ikonie pokazuje liczbę niezapłaconych płatności i nie da się jej zamknąć — znika, kiedy odhaczysz wszystko.")
                bullet("Powiadomienia wracają do trzech razy dziennie przez trzy tygodnie, dopóki nie oznaczysz płatności.")
                bullet("Prosto z powiadomienia możesz nacisnąć Zapłacone albo Przypomnij za godzinę, bez wchodzenia do aplikacji.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("Jak działa przypominanie")
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var authorizationLabel: String {
        switch store.authorizationStatus {
        case .authorized: return "udzielona"
        case .provisional: return "tymczasowa"
        case .denied: return "odmowa"
        case .notDetermined: return "nieustalona"
        case .ephemeral: return "tymczasowa"
        @unknown default: return "nieznana"
        }
    }

    private var authorizationColor: Color {
        switch store.authorizationStatus {
        case .authorized, .provisional: return .green
        case .denied: return .red
        default: return .orange
        }
    }
}
