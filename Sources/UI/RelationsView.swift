import SwiftUI

@MainActor
struct RelationsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            Group {
                if let result = state.result {
                    List {
                        Section("Reciprocità") {
                            link("Non ti seguono indietro",
                                 systemImage: "arrow.uturn.left",
                                 tint: .orange,
                                 accounts: result.notFollowingBack,
                                 explanation: "Account che segui e che non ti seguono.")
                            link("Ti seguono, non li segui",
                                 systemImage: "heart",
                                 tint: .pink,
                                 accounts: result.fans,
                                 explanation: "Ti seguono senza che tu li segua.")
                            link("Reciproci",
                                 systemImage: "arrow.left.arrow.right",
                                 tint: .teal,
                                 accounts: result.mutuals,
                                 explanation: "Vi seguite a vicenda.")
                        }

                        Section("Movimenti") {
                            link("Smessi di seguire di recente",
                                 systemImage: "person.badge.minus",
                                 tint: .red,
                                 accounts: result.recentlyUnfollowed,
                                 explanation: "Dalla lista che Instagram include nell'export.")
                            link("Richieste inviate in sospeso",
                                 systemImage: "paperplane",
                                 tint: .blue,
                                 accounts: result.pendingSent,
                                 explanation: "Richieste di follow che hai mandato e non ancora accettate.")
                            link("Richieste ricevute",
                                 systemImage: "tray.and.arrow.down",
                                 tint: .blue,
                                 accounts: result.requestsReceived,
                                 explanation: "Richieste in attesa di una tua risposta.")
                        }

                        Section("Liste") {
                            link("Amici più stretti",
                                 systemImage: "star",
                                 tint: .yellow,
                                 accounts: result.closeFriends,
                                 explanation: "La tua lista amici più stretti.")
                            link("Bloccati",
                                 systemImage: "hand.raised",
                                 tint: .gray,
                                 accounts: result.blocked,
                                 explanation: "Account che hai bloccato.")
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    EmptyState(title: "Servono le liste follower",
                               message: "Queste analisi si calcolano solo sull'export dei dati o sulle liste incollate a mano. L'API ufficiale di Instagram non espone chi ti segue.",
                               systemImage: "person.2.slash")
                }
            }
            .navigationTitle("Relazioni")
        }
    }

    @ViewBuilder
    private func link(_ title: String,
                      systemImage: String,
                      tint: Color,
                      accounts: [Account],
                      explanation: String) -> some View {
        NavigationLink {
            AccountListScreen(title: title, explanation: explanation, accounts: accounts)
        } label: {
            HStack {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage).foregroundStyle(tint)
                }
                Spacer()
                Text(accounts.count.grouped)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(accounts.isEmpty)
    }
}
