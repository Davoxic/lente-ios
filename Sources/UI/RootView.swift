import SwiftUI

@MainActor
struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            SearchView()
                .tabItem { Label("Cerca", systemImage: "magnifyingglass") }
            OverviewView()
                .tabItem { Label("Panoramica", systemImage: "chart.line.uptrend.xyaxis") }
            RelationsView()
                .tabItem { Label("Relazioni", systemImage: "person.2") }
            ActivityView()
                .tabItem { Label("Attività", systemImage: "waveform.path.ecg") }
            DataView()
                .tabItem { Label("Dati", systemImage: "tray.and.arrow.down") }
        }
        .alert("Qualcosa non ha funzionato",
               isPresented: Binding(get: { state.errorMessage != nil },
                                    set: { if !$0 { state.errorMessage = nil } })) {
            Button("Ok", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}
