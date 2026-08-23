# Płatności

Prywatna aplikacja na iPhone do pilnowania stałych płatności miesięcznych.
Budowana z Windowsa, bez Maca, bez App Store.

## Najważniejsze: jak działa „przypomnienie na wierzchu"

**iOS nie ma przyklejonego powiadomienia.** Nie istnieje odpowiednik androidowego
ongoing notification — nie da się zostawić czegoś na ekranie do odwołania.
Jedyny wyjątek, Critical Alerts, wymaga osobnej zgody Apple wydawanej aplikacjom
medycznym i bezpieczeństwa.

Dlatego przypominanie stoi na trzech filarach, z których każdy działa bez
jakichkolwiek uprawnień od Apple:

1. **Plakietka na ikonie** pokazuje liczbę nieopłaconych płatności. Wisi
   bezterminowo i nie da się jej zamknąć gestem — znika dopiero, kiedy odhaczysz
   wszystko. To jedyny element iOS zachowujący się naprawdę „na stałe".
2. **Nawracające powiadomienia** — do trzech razy dziennie przez trzy tygodnie,
   dopóki płatność nie zostanie oznaczona. Zamknięcie jednego niczego nie kończy,
   następne przyjdzie za kilka godzin. Grupują się w jeden stos na ekranie
   blokady, więc nie zaśmiecają go osobnymi wpisami.
3. **Akcje wprost z powiadomienia** — „Zapłacone" i „Przypomnij za godzinę",
   bez wchodzenia do aplikacji.

Do tego dochodzi **odświeżanie w tle** (`BGAppRefreshTask`), które przesuwa okno
zaplanowanych powiadomień do przodu, więc przypomnienia nie wygasają po
wyczerpaniu zaplanowanej puli.

Jest jeszcze czwarty filar, **widget na ekran blokady** — ten faktycznie wisi na
ekranie bezterminowo. Wymaga jednak płatnego konta Apple; szczegóły niżej.

## Uruchomienie: z Windowsa na iPhone, za darmo

Nie potrzebujesz Maca ani Xcode. Kompilacja dzieje się na darmowym runnerze
macOS w GitHub Actions, a podpisanie — na samym telefonie.

### 1. Wrzuć projekt na GitHub

```bash
git init
git add .
git commit -m "Płatności"
git branch -M main
git remote add origin git@github.com:TWOJA-NAZWA/platnosci.git
git push -u origin main
```

Repozytorium **publiczne** ma darmowe runnery macOS bez limitu. Prywatne ma
około 200 minut miesięcznie, co przy buildzie trwającym kilka minut też
wystarcza z zapasem.

### 2. Odbierz plik IPA

Push na `main` uruchamia workflow automatycznie. Wejdź w zakładkę **Actions**,
otwórz ostatni przebieg i pobierz artefakt `Platnosci-ipa`. W środku jest
`Platnosci.ipa` — **niepodpisany**, i to jest zamierzone: podpisywanie omijamy
w całości (`CODE_SIGNING_ALLOWED=NO`), więc żadne certyfikaty Apple nie są
potrzebne na tym etapie.

### 3. Podpisz i zainstaluj na telefonie

Zainstaluj **SideStore** na iPhonie (jednorazowa konfiguracja, opisana na
[docs.sidestore.io](https://docs.sidestore.io)) i wrzuć do niego `Platnosci.ipa`.
SideStore podpisze aplikację certyfikatem z Twojego zwykłego, darmowego Apple ID
i sam będzie go odświeżał co 7 dni, dopóki masz włączony LocalDevVPN.

Po pierwszym uruchomieniu zaakceptuj zgodę na powiadomienia, a potem wejdź w
**Ustawienia → Wyślij powiadomienie testowe**, żeby od razu sprawdzić, czy
wszystko działa.

Zmień `PRODUCT_BUNDLE_IDENTIFIER` w `project.yml` z `com.example.platnosci` na
coś swojego, jeśli chcesz — pamiętaj wtedy zaktualizować także
`BGTaskSchedulerPermittedIdentifiers` i `BackgroundRefresh.taskIdentifier`.

## Wariant z widgetem (wymaga 99 USD/rok)

Widget jest osobnym procesem systemowym i może czytać dane aplikacji wyłącznie
przez **App Groups**. Darmowe Apple ID (Personal Team) nie dostaje tego
uprawnienia — SideStore ma to nawet rozdzielone na dwa pliki entitlements,
darmowy i płatny. Przy darmowym certyfikacie instalacja z tym uprawnieniem się
nie powiedzie.

Jeśli masz płatne konto Apple Developer, uruchom workflow ręcznie
(**Actions → Build IPA → Run workflow**) i wybierz `project.widget.yml`.
Dostaniesz widget na ekran główny oraz na ekran blokady, w wariantach
okrągłym, prostokątnym i liniowym.

Kod jest przygotowany na oba scenariusze: `StorageLocation` sam wykrywa, czy
kontener współdzielony jest dostępny, i po cichu wraca do prywatnego katalogu
aplikacji, jeśli nie jest. Aplikacja działa identycznie w obu wariantach —
różni je tylko obecność widgetu. Aktualny stan widać w
**Ustawienia → Diagnostyka → Dane widgetu**.

## Struktura

```
project.yml              Definicja projektu — .xcodeproj powstaje na runnerze
project.widget.yml       Wariant z widgetem (płatne konto Apple)
.github/workflows/       Build IPA + testy
Sources/Shared/          Logika i modele, wyłącznie Foundation
Sources/App/             Aplikacja iOS: SwiftUI, powiadomienia, tło
Sources/Widget/          Widget (opcjonalny)
Tests/                   Testy logiki, uruchamiane na macOS bez symulatora
```

W repozytorium **nie ma** pliku `.xcodeproj` — generuje go XcodeGen z
`project.yml`. Dzięki temu nie trzeba mieć Xcode, żeby projekt istniał, a plik
konfiguracji da się czytać i scalać w gicie jak normalny tekst.

`Sources/Shared` celowo nie importuje SwiftUI ani UIKit. To ograniczenie jest
warte pilnowania: dzięki niemu testy chodzą jako zwykły target macOS, bez
symulatora iOS, co w CI jest znacznie szybsze i mniej kruche.

## Decyzje projektowe

**Kwoty na `Decimal`, nie na `Double`.** `Double` nie zapisuje dokładnie 0.1,
więc sumowanie kwot daje groszowe rozjazdy.

**Zapis do pliku JSON, nie do `UserDefaults`.** Plik jest zapisywany atomowo,
da się go podejrzeć i naprawić, a uszkodzoną zawartość odkładamy na bok zamiast
po cichu zwracać pustkę.

**Wersjonowany schemat i ręczne dekodery.** Każdy model ma `init(from:)` z
wartościami domyślnymi, więc dodanie nowego pola w przyszłej wersji nie wysypie
dekodowania starych danych. To najgroźniejsza pułapka tego typu aplikacji:
jedno nieudane dekodowanie za `try?` i cała historia przepada bez śladu.

**Historia trzyma kopię kwoty i nazwy.** Podniesienie kwoty dzisiaj nie
przepisuje tego, ile zapłaciłeś rok temu. Wpisy przeżywają też usunięcie
płatności.

**Termin od 1 do 31 z przycinaniem.** Termin „31" wypada ostatniego dnia
lutego, a nie przelewa się na marzec. Nie ma sztucznego ograniczenia do 28.

**Planer przypomnień jako czysta funkcja.** `ReminderPlanner` nie zna
`UserNotifications` — produkuje listę danych, którą warstwa aplikacji tłumaczy
na obiekty systemowe. Dlatego limit 64 powiadomień, przypadek płatności po
terminie i podział budżetu między płatności są pokryte testami.

**Budżet powiadomień dzielony przeplotem.** iOS trzyma maksymalnie 64
oczekujące powiadomienia i nadwyżkę wyrzuca po cichu. Sam tryb natarczywy chce
45 na miesiąc, więc bez pilnowania limitu przy kilku płatnościach część
przypomnień nigdy by nie dotarła. Planer rozdaje pulę po jednym na płatność,
zamiast pozwolić pierwszej zająć wszystko.

## Znane ograniczenia

- Certyfikat z darmowego Apple ID wygasa po 7 dniach. SideStore odświeża go sam,
  ale wymaga włączonego LocalDevVPN.
- Odświeżanie w tle uruchamia się, kiedy system uzna to za stosowne — nie ma na
  iOS niczego, co gwarantuje wykonanie o konkretnej godzinie. Plan jest
  przeliczany także przy każdym otwarciu aplikacji, więc nie jest to problem.
- `.timeSensitive` (przebijanie trybu skupienia) jest ustawiane w kodzie, ale
  pełny efekt wymaga uprawnienia z płatnego konta. Bez niego powiadomienia
  działają jak zwykłe.
- Brak synchronizacji z iCloud. Dane żyją na jednym telefonie.
