import SwiftUI
import UIKit
import Charts

@MainActor
struct WatchlistView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingAdd = false
    @State private var newUsername = ""

    var body: some View {
        NavigationStack {
            Group {
                if state.watched.isEmpty {
                    EmptyState(title: "Nessun profilo monitorato",
                               message: "Aggiungi un profilo col + in alto. Ogni volta che vuoi registri i suoi numeri e l'app tiene lo storico, la variazione e il grafico.",
                               systemImage: "binoculars")
                } else {
                    List {
                        ForEach(state.watched) { profile in
                            NavigationLink {
                                WatchedProfileView(profileID: profile.id)
                            } label: {
                                WatchRow(profile: profile)
                            }
                        }
                        .onDelete(perform: remove)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Monitorati")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newUsername = ""
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Aggiungi profilo", isPresented: $showingAdd) {
                TextField("nome utente", text: $newUsername)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Annulla", role: .cancel) { }
                Button("Aggiungi") {
                    state.addWatched(newUsername)
                    newUsername = ""
                }
            } message: {
                Text("Senza @, oppure incolla il link del profilo.")
            }
        }
    }

    private func remove(at offsets: IndexSet) {
        for index in offsets where index < state.watched.count {
            state.removeWatched(state.watched[index])
        }
    }
}

@MainActor
struct WatchRow: View {
    var profile: WatchedProfile

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("@" + profile.username)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let delta = profile.followerDelta {
                DeltaBadge(value: delta)
            }
        }
    }

    private var subtitle: String {
        guard let latest = profile.latest else { return "Nessuna rilevazione" }
        var parts: [String] = []
        if let followers = latest.followers { parts.append("\(followers.grouped) follower") }
        if let following = latest.following { parts.append("\(following.grouped) seguiti") }
        parts.append(latest.date.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}

@MainActor
struct DeltaBadge: View {
    var value: Int

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.15)))
            .foregroundStyle(tint)
    }

    private var text: String {
        if value > 0 { return "+\(value.grouped)" }
        if value < 0 { return "−\(abs(value).grouped)" }
        return "="
    }

    private var tint: Color {
        if value > 0 { return .green }
        if value < 0 { return .red }
        return .secondary
    }
}

// MARK: - Detail

@MainActor
struct WatchedProfileView: View {
    var profileID: UUID
    @EnvironmentObject private var state: AppState
    @Environment(\.openURL) private var openURL

    @State private var showingManualEntry = false
    @State private var autoFailureMessage: String?

    private var profile: WatchedProfile? {
        state.watched.first { $0.id == profileID }
    }

    var body: some View {
        Group {
            if let profile {
                content(profile)
            } else {
                EmptyState(title: "Profilo rimosso",
                           message: "Questo profilo non è più nella lista.",
                           systemImage: "binoculars")
            }
        }
        .navigationTitle(profile.map { "@" + $0.username } ?? "Profilo")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ profile: WatchedProfile) -> some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Button {
                        openProfile(profile)
                    } label: {
                        Label("Apri su Instagram", systemImage: "arrow.up.forward.app")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showingManualEntry = true
                    } label: {
                        Label("Segna numeri", systemImage: "plus.circle")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 2)

                Button {
                    Task { autoFailureMessage = await state.fetchReading(for: profile) }
                } label: {
                    Label("Prova la rilevazione automatica", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.footnote)
                }
                .disabled(state.isWorking)

                if let autoFailureMessage {
                    Text(autoFailureMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("La rilevazione automatica usa l'endpoint ufficiale Business Discovery: funziona se il tuo account è professionale e quello osservato è professionale e pubblico. Negli altri casi apri il profilo, guardi i numeri e li segni: due tocchi.")
            }

            if let latest = profile.latest {
                Section("Ultima rilevazione") {
                    LabeledContent("Follower", value: latest.followers.map { $0.grouped } ?? "–")
                    LabeledContent("Seguiti", value: latest.following.map { $0.grouped } ?? "–")
                    if let posts = latest.posts {
                        LabeledContent("Contenuti", value: posts.grouped)
                    }
                    LabeledContent("Quando", value: latest.date.formatted(date: .abbreviated, time: .shortened))
                    if let delta = profile.followerDelta {
                        HStack {
                            Text("Variazione follower")
                            Spacer()
                            DeltaBadge(value: delta)
                        }
                    }
                    if let rate = profile.dailyRate {
                        LabeledContent("Media al giorno", value: String(format: "%+.1f", rate))
                    }
                }
            }

            chartSection(profile)

            if profile.isSelf {
                Section {
                    Text("Questo è il tuo account: per sapere anche *chi* sono i follower che hai guadagnato o perso, importa l'export dalla scheda Dati. Per gli account altrui il \"chi\" non è ottenibile in alcun modo lecito.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            historySection(profile)

            Section {
                Button(role: .destructive) {
                    state.removeWatched(profile)
                } label: {
                    Label("Togli dal monitoraggio", systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingManualEntry) {
            ReadingEntrySheet(profile: profile)
                .environmentObject(state)
        }
    }

    @ViewBuilder
    private func chartSection(_ profile: WatchedProfile) -> some View {
        let followers = profile.followerSeries
        if followers.count > 1 {
            Section("Andamento follower") {
                Chart(followers) { bucket in
                    LineMark(x: .value("Data", bucket.date),
                             y: .value("Follower", bucket.count))
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
                    PointMark(x: .value("Data", bucket.date),
                              y: .value("Follower", bucket.count))
                    .foregroundStyle(Color.accentColor)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 180)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func historySection(_ profile: WatchedProfile) -> some View {
        let readings = profile.sortedReadings.reversed()
        if !readings.isEmpty {
            Section("Storico · \(profile.readings.count)") {
                ForEach(Array(readings)) { reading in
                    HStack(spacing: 10) {
                        Image(systemName: reading.source.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line(for: reading))
                                .font(.subheadline)
                                .monospacedDigit()
                            Text(reading.date.formatted(date: .abbreviated, time: .shortened)
                                 + " · " + reading.source.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            state.deleteReading(reading, from: profile)
                        } label: {
                            Label("Elimina", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func line(for reading: ProfileReading) -> String {
        var parts: [String] = []
        if let followers = reading.followers { parts.append("\(followers.grouped) follower") }
        if let following = reading.following { parts.append("\(following.grouped) seguiti") }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    private func openProfile(_ profile: WatchedProfile) {
        if let appURL = profile.appURL, UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL)
            return
        }
        if let webURL = profile.webURL { openURL(webURL) }
    }
}

// MARK: - Manual reading

@MainActor
struct ReadingEntrySheet: View {
    var profile: WatchedProfile
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var followers = ""
    @State private var following = ""
    @FocusState private var focused: Field?

    private enum Field { case followers, following }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Apri @\(profile.username) su Instagram, leggi i due numeri e scrivili qui.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        if let appURL = profile.appURL, UIApplication.shared.canOpenURL(appURL) {
                            openURL(appURL)
                        } else if let webURL = profile.webURL {
                            openURL(webURL)
                        }
                    } label: {
                        Label("Apri il profilo", systemImage: "arrow.up.forward.app")
                            .font(.subheadline)
                    }
                }

                Section("Numeri") {
                    HStack {
                        Text("Follower")
                        Spacer()
                        TextField("0", text: $followers)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 140)
                            .focused($focused, equals: .followers)
                    }
                    HStack {
                        Text("Seguiti")
                        Spacer()
                        TextField("0", text: $following)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 140)
                            .focused($focused, equals: .following)
                    }
                }

                Section {
                    Text("Puoi compilarne anche uno solo. La data viene registrata da sola.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Segna numeri")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { focused = .followers }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        state.recordReading(followers: parse(followers),
                                            following: parse(following),
                                            source: .manual,
                                            for: profile)
                        dismiss()
                    }
                    .disabled(parse(followers) == nil && parse(following) == nil)
                }
            }
        }
    }

    private func parse(_ text: String) -> Int? {
        CountText.parse(text)
    }
}
