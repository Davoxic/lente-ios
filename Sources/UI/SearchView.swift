import SwiftUI
import UIKit

@MainActor
struct SearchView: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""

    private var results: [ProfileCard] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return state.index.suggestions() }
        return state.index.search(trimmed)
    }

    var body: some View {
        NavigationStack {
            Group {
                if state.index.isEmpty {
                    EmptyState(title: "Nessun dato da cercare",
                               message: "Importa l'export dalla scheda Dati: da lì in poi puoi cercare qualsiasi account che compare nei tuoi follower, nei tuoi seguiti o nelle tue interazioni.",
                               systemImage: "magnifyingglass")
                } else {
                    List {
                        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Section {
                                Text("\(state.index.count.grouped) account nei tuoi dati. Scrivi un nome utente per vedere la tua situazione con quella persona.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if !results.isEmpty {
                                Section("Con cui interagisci di più") {
                                    ForEach(results) { card in row(card) }
                                }
                            }
                        } else if results.isEmpty {
                            Section {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Nessun account con questo nome nei tuoi dati.")
                                        .font(.subheadline)
                                    Text("Vuol dire che non ti segue, non lo segui e non risulta una tua interazione. Puoi comunque aprirlo su Instagram.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    OpenOnInstagramButton(username: cleanedQuery)
                                }
                                .padding(.vertical, 4)
                            }
                        } else {
                            Section("\(results.count) risultati") {
                                ForEach(results) { card in row(card) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Cerca")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Nome utente")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
    }

    private var cleanedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
    }

    @ViewBuilder
    private func row(_ card: ProfileCard) -> some View {
        NavigationLink {
            ProfileCardView(card: card)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: card.relationship.symbol)
                    .foregroundStyle(tint(for: card.relationship))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("@" + card.username)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(card.relationship.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if card.interactions > 0 {
                    Text("\(card.interactions)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func tint(for relationship: ProfileCard.Relationship) -> Color {
        switch relationship {
        case .mutual: return .teal
        case .onlyTheyFollow: return .pink
        case .onlyYouFollow: return .orange
        case .none: return .secondary
        }
    }
}

// MARK: - Detail

@MainActor
struct ProfileCardView: View {
    var card: ProfileCard

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("@" + card.username)
                        .font(.title2.weight(.semibold))
                    Label(card.relationship.label, systemImage: card.relationship.symbol)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    OpenOnInstagramButton(username: card.username)
                        .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }

            Section("Follow") {
                fact("Ti segue", card.followsYou, since: card.followedYouSince)
                fact("Lo segui", card.youFollow, since: card.youFollowedSince)
                if card.pendingRequestSent {
                    flag("Richiesta inviata, in attesa", "paperplane", .blue)
                }
                if card.requestReceived {
                    flag("Ti ha mandato una richiesta", "tray.and.arrow.down", .blue)
                }
                if card.recentlyUnfollowed {
                    flag("Hai smesso di seguirlo di recente", "person.badge.minus", .red)
                }
            }

            Section("Le tue interazioni") {
                LabeledContent("Like messi", value: card.likesGiven.grouped)
                LabeledContent("Commenti", value: card.commentsGiven.grouped)
                if card.interactions == 0 {
                    Text("Nell'export non risulta una tua interazione con questo account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if card.isCloseFriend || card.isBlocked || card.isRestricted || card.isHidden {
                Section("Liste") {
                    if card.isCloseFriend { flag("Amici più stretti", "star", .yellow) }
                    if card.isBlocked { flag("Bloccato", "hand.raised", .gray) }
                    if card.isRestricted { flag("Limitato", "exclamationmark.shield", .gray) }
                    if card.isHidden { flag("Storie nascoste a questo account", "eye.slash", .gray) }
                }
            }

            Section {
                Text("Queste informazioni vengono dall'export del tuo account. Per vedere il profilo vero, anche se è privato e tu lo segui, apri Instagram: sei già collegato lì.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(card.username)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fact(_ label: String, _ value: Bool, since: Date?) -> some View {
        HStack {
            Image(systemName: value ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(value ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                if value, let since {
                    Text("dal " + since.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(value ? "Sì" : "No")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(value ? Color.green : Color.secondary)
        }
    }

    private func flag(_ text: String, _ symbol: String, _ tint: Color) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }
}

// MARK: - Open in Instagram

@MainActor
struct OpenOnInstagramButton: View {
    var username: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            open()
        } label: {
            Label("Apri su Instagram", systemImage: "arrow.up.forward.app")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.borderedProminent)
        .disabled(username.isEmpty)
    }

    private func open() {
        guard !username.isEmpty else { return }
        // Prefer the installed app, fall back to the website.
        if let appURL = URL(string: "instagram://user?username=\(username)"),
           UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL)
            return
        }
        if let webURL = URL(string: "https://www.instagram.com/\(username)/") {
            openURL(webURL)
        }
    }
}
