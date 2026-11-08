import SwiftUI

@MainActor
struct ManualEntryView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var followers = ""
    @State private var following = ""

    private var followerCount: Int { ManualImport.handles(from: followers).count }
    private var followingCount: Int { ManualImport.handles(from: following).count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Un nome utente per riga. Vanno bene anche @nome o il link completo al profilo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Chi ti segue — \(followerCount) riconosciuti") {
                    TextEditor(text: $followers)
                        .frame(minHeight: 140)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Chi segui — \(followingCount) riconosciuti") {
                    TextEditor(text: $following)
                        .frame(minHeight: 140)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Liste a mano")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Analizza") {
                        state.importManual(followers: followers, following: following)
                        dismiss()
                    }
                    .disabled(followerCount == 0 && followingCount == 0)
                }
            }
        }
    }
}

@MainActor
struct TokenEntryView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Token di accesso") {
                    TextEditor(text: $token)
                        .frame(minHeight: 120)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Come ottenerlo") {
                    Text("Serve un account Instagram professionale (Business o Creator).")
                        .font(.footnote)
                    Text("1. Crea un'app su developers.facebook.com e aggiungi il prodotto Instagram.")
                        .font(.footnote)
                    Text("2. Collega il tuo account professionale e genera un token con i permessi di lettura su profilo e insights.")
                        .font(.footnote)
                    Text("3. Scambialo con un token a lunga durata e incollalo qui.")
                        .font(.footnote)
                }

                Section {
                    Text("Il token resta nel portachiavi di questo dispositivo e viene usato solo per chiamare direttamente i server ufficiali di Instagram.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("API ufficiale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        state.saveToken(token)
                        dismiss()
                        Task { await state.refreshFromAPI() }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
