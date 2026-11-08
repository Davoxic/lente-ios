import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct DataView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingFileImporter = false
    @State private var showingManualEntry = false
    @State private var showingTokenSheet = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("I tre metodi sono in ordine di affidabilità. Il primo basta quasi sempre.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("1 · Export dati — consigliato") {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Apri l'archivio ZIP", systemImage: "shippingbox")
                    }
                    NavigationLink {
                        ExportGuideView()
                    } label: {
                        Label("Come si scarica", systemImage: "questionmark.circle")
                    }
                    Text("Liste follower complete, date, interazioni. Nessun login, nessuna chiamata di rete, nessun rischio per l'account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("2 · API ufficiale — fallback") {
                    Button {
                        showingTokenSheet = true
                    } label: {
                        Label(state.hasToken ? "Modifica token" : "Incolla un token",
                              systemImage: "key")
                    }
                    Button {
                        Task { await state.refreshFromAPI() }
                    } label: {
                        Label("Aggiorna dalle API", systemImage: "arrow.clockwise")
                    }
                    .disabled(!state.hasToken || state.isWorking)
                    if state.hasToken {
                        Button(role: .destructive) {
                            state.clearToken()
                        } label: {
                            Label("Rimuovi token", systemImage: "trash")
                        }
                    }
                    Text("Conteggi e metriche ufficiali in tempo reale. Instagram non espone a nessuna app la lista di chi ti segue, quindi la reciprocità qui non si calcola.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("3 · Inserimento manuale — ultima rete") {
                    Button {
                        showingManualEntry = true
                    } label: {
                        Label("Incolla le liste", systemImage: "square.and.pencil")
                    }
                    Text("Se non hai l'export e non vuoi collegare le API: incolli i nomi utente, uno per riga. Gli import successivi vengono confrontati tra loro.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !state.snapshots.isEmpty {
                    Section("Snapshot salvati") {
                        ForEach(state.snapshots.reversed()) { snapshot in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                Text(detail(for: snapshot))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: deleteSnapshots)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Cancella tutti i dati locali", systemImage: "trash")
                    }
                } footer: {
                    Text("Tutto resta su questo telefono: snapshot in Documenti, token nel portachiavi. Niente viene inviato a server di terze parti.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Dati")
            .overlay {
                if state.isWorking {
                    ProgressOverlay(note: state.progressNote)
                }
            }
            .fileImporter(isPresented: $showingFileImporter,
                          allowedContentTypes: [.zip],
                          allowsMultipleSelection: false) { outcome in
                switch outcome {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await state.importExport(at: url) }
                case .failure(let error):
                    state.errorMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualEntryView()
                    .environmentObject(state)
            }
            .sheet(isPresented: $showingTokenSheet) {
                TokenEntryView()
                    .environmentObject(state)
            }
            .alert("Cancellare tutto?", isPresented: $showingDeleteConfirmation) {
                Button("Annulla", role: .cancel) { }
                Button("Cancella", role: .destructive) { state.deleteEverything() }
            } message: {
                Text("Vengono eliminati gli snapshot e l'analisi corrente. Il token va rimosso a parte.")
            }
        }
    }

    private func detail(for snapshot: Snapshot) -> String {
        if let label = snapshot.label, snapshot.followers.isEmpty {
            return "\(snapshot.source.label) · \(label)"
        }
        return "\(snapshot.source.label) · \(snapshot.followerCount.grouped) follower · \(snapshot.followingCount.grouped) seguiti"
    }

    private func deleteSnapshots(at offsets: IndexSet) {
        let reversed = Array(state.snapshots.reversed())
        for index in offsets where index < reversed.count {
            state.deleteSnapshot(reversed[index])
        }
    }
}

// MARK: - Progress

@MainActor
struct ProgressOverlay: View {
    var note: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                if let note {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }
}

// MARK: - Guide

@MainActor
struct ExportGuideView: View {
    var body: some View {
        List {
            Section("Dove") {
                Text("Nell'app Instagram: Impostazioni → Centro gestione account → Le tue informazioni e autorizzazioni → Scarica le tue informazioni.")
                    .font(.subheadline)
            }
            Section("Come richiederlo") {
                step(1, "Scegli di scaricare le informazioni del tuo account.")
                step(2, "Formato: JSON. È obbligatorio, l'HTML qui non si legge.")
                step(3, "Intervallo: tutto il periodo.")
                step(4, "Seleziona almeno \"Follower e seguiti\" e \"La tua attività su Instagram\". Puoi escludere foto e video: pesano tanto e qui non servono.")
                step(5, "Instagram manda un link via email, di solito entro qualche ora.")
                step(6, "Scarica lo ZIP sul telefono e aprilo da qui con \"Apri l'archivio ZIP\".")
            }
            Section {
                Text("L'archivio non viene mai caricato da nessuna parte: viene letto in locale e scartato. Restano solo i conteggi e le liste di nomi utente negli snapshot.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Scaricare l'export")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                .foregroundStyle(Color.accentColor)
            Text(text).font(.subheadline)
        }
    }
}
