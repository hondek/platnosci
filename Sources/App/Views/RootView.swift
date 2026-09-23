import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            DashboardView(kind: .outgoing)
                .tabItem { Label("Płatności", systemImage: "banknote") }

            DashboardView(kind: .incoming)
                .tabItem { Label("Należności", systemImage: "arrow.down.circle") }

            ChoresView()
                .tabItem { Label("Przypomnienia", systemImage: "bell") }

            MedicationsView()
                .tabItem { Label("Leki", systemImage: "pills") }

            LessonsView()
                .tabItem { Label("Lekcje", systemImage: "calendar") }
        }
    }
}
