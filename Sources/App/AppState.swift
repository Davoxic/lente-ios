import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {

    enum Source: String, CaseIterable, Identifiable {
        case export
        case api
        case manual

        var id: String { rawValue }

        var title: String {
            switch self {
            case .export: return "Export dati"
            case .api: return "API ufficiale"
            case .manual: return "Inserimento manuale"
            }
        }

        var subtitle: String {
            switch self {
            case .export: return "Il più completo. Nessun login, funziona offline."
            case .api: return "Metriche live. Niente liste follower."
            case .manual: return "Rete di sicurezza: incolli le liste a mano."
            }
        }

        var symbol: String {
            switch self {
            case .export: return "shippingbox"
            case .api: return "antenna.radiowaves.left.and.right"
            case .manual: return "square.and.pencil"
            }
        }
    }

    @Published var result: AnalysisResult?
    @Published var isWorking = false
    @Published var progressNote: String?
    @Published var errorMessage: String?
    @Published var snapshots: [Snapshot] = []
    @Published var activeSource: Source = .export
    @Published var index = ProfileIndex()
    @Published var watched: [WatchedProfile] = []

    // Official API state
    @Published var graphProfile: GraphProfile?
    @Published var graphMedia: [GraphMedia] = []
    @Published var graphInsights: [GraphInsightValue] = []
    @Published var hasToken: Bool = TokenStore.hasToken

    private let store = SnapshotStore()
    private let watchlist = WatchlistStore()

    init() {
        snapshots = store.snapshots
        watched = watchlist.profiles
        // Restore the last analysis so reopening the app shows data straight away.
        if let saved = AnalysisArchive.load() {
            result = saved.result
            index = saved.index
        }
    }

    var latestDiff: SnapshotDiff? { store.latestDiff }

    var hasData: Bool { result != nil || graphProfile != nil }

    /// Growth series: prefers the dates inside the export, falls back to the
    /// history of snapshots taken on this device.
    var followerSeries: [TimeBucket] {
        if let growth = result?.followerGrowth, growth.count > 1 { return growth }
        let series = store.followerSeries()
        return series.count > 1 ? series : []
    }

    var followerSeriesIsFromSnapshots: Bool {
        ((result?.followerGrowth.count) ?? 0) <= 1
    }

    // MARK: - Export import

    func importExport(at url: URL) async {
        isWorking = true
        errorMessage = nil
        progressNote = "Apro l'archivio…"
        defer { isWorking = false; progressNote = nil }

        // The picked file lives outside the sandbox until it is copied in.
        var scoped = false
        if url.startAccessingSecurityScopedResource() { scoped = true }
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let working = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString).zip")
        do {
            try? FileManager.default.removeItem(at: working)
            try FileManager.default.copyItem(at: url, to: working)
        } catch {
            errorMessage = "Non riesco a leggere il file selezionato: \(error.localizedDescription)"
            return
        }
        defer { try? FileManager.default.removeItem(at: working) }

        progressNote = "Leggo i dati…"
        let parsed: Result<ExportContents, Error> = await Task.detached(priority: .userInitiated) {
            do { return .success(try ExportParser.parse(archiveAt: working)) }
            catch { return .failure(error) }
        }.value

        switch parsed {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let contents):
            if contents.isEmpty {
                errorMessage = contents.warnings.first
                    ?? "L'archivio non contiene dati riconoscibili."
                return
            }
            progressNote = "Calcolo le metriche…"
            let analysis = Analyzer.analyze(contents, source: .dataExport)
            let lookup = ProfileIndex(contents)
            let snapshot = Analyzer.snapshot(from: contents, source: .dataExport)
            store.append(snapshot)
            snapshots = store.snapshots
            result = analysis
            index = lookup
            activeSource = .export
            AnalysisArchive.save(result: analysis, index: lookup)

            // The owner's own account joins the watchlist automatically, with the
            // counts the export just produced as its first reading.
            if let own = contents.username, addWatched(own, isSelf: true),
               let mine = watchlist.profiles.first(where: { $0.username.lowercased() == own.lowercased() }) {
                recordReading(followers: analysis.followerCount,
                              following: analysis.followingCount,
                              source: .ownExport,
                              for: mine)
            }
        }
    }

    // MARK: - Manual

    func importManual(followers: String, following: String) {
        let contents = ManualImport.contents(followers: followers, following: following)
        guard !contents.followers.isEmpty || !contents.following.isEmpty else {
            errorMessage = "Nessun nome utente riconosciuto. Incollane uno per riga."
            return
        }
        let analysis = Analyzer.analyze(contents, source: .manual)
        let lookup = ProfileIndex(contents)
        let snapshot = Analyzer.snapshot(from: contents, source: .manual)
        store.append(snapshot)
        snapshots = store.snapshots
        result = analysis
        index = lookup
        activeSource = .manual
        errorMessage = nil
        AnalysisArchive.save(result: analysis, index: lookup)
    }

    // MARK: - Official API

    func saveToken(_ token: String) {
        TokenStore.save(token)
        hasToken = TokenStore.hasToken
    }

    func clearToken() {
        TokenStore.clear()
        hasToken = false
        graphProfile = nil
        graphMedia = []
        graphInsights = []
    }

    func refreshFromAPI() async {
        guard let token = TokenStore.load() else {
            errorMessage = GraphAPIError.missingToken.localizedDescription
            return
        }
        isWorking = true
        errorMessage = nil
        progressNote = "Interrogo l'API…"
        defer { isWorking = false; progressNote = nil }

        let client = GraphAPIClient(token: token)
        do {
            let profile = try await client.profile()
            graphProfile = profile
            activeSource = .api

            // Media and insights are best effort: a missing permission on one of
            // them should not wipe out the profile figures already fetched.
            graphMedia = (try? await client.media()) ?? []
            graphInsights = (try? await client.accountInsights()) ?? []

            if let followers = profile.followersCount {
                var snapshot = Snapshot(source: .graphAPI)
                snapshot.label = "\(followers) follower"
                // The API exposes counts but not the member lists, so the
                // snapshot records the count only.
                snapshot.followers = []
                snapshot.following = []
                store.append(snapshot)
                snapshots = store.snapshots
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }


    // MARK: - Watchlist

    @discardableResult
    func addWatched(_ username: String, isSelf: Bool = false) -> Bool {
        guard watchlist.add(username: username, isSelf: isSelf) != nil else {
            errorMessage = "\"\(username)\" non è un nome utente valido."
            return false
        }
        watched = watchlist.profiles
        return true
    }

    func removeWatched(_ profile: WatchedProfile) {
        watchlist.remove(profile)
        watched = watchlist.profiles
    }

    func updateNote(_ note: String?, for profile: WatchedProfile) {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        watchlist.updateNote((trimmed?.isEmpty ?? true) ? nil : trimmed, for: profile.id)
        watched = watchlist.profiles
    }

    func recordReading(followers: Int?, following: Int?, posts: Int? = nil,
                       source: ProfileReading.Source, for profile: WatchedProfile) {
        guard followers != nil || following != nil else { return }
        let reading = ProfileReading(followers: followers, following: following,
                                     posts: posts, source: source)
        watchlist.record(reading, for: profile.id)
        watched = watchlist.profiles
    }

    func deleteReading(_ reading: ProfileReading, from profile: WatchedProfile) {
        watchlist.deleteReading(reading.id, from: profile.id)
        watched = watchlist.profiles
    }

    func current(_ profile: WatchedProfile) -> WatchedProfile {
        watchlist.profile(with: profile.id) ?? profile
    }

    /// Tries the official endpoint. Returns nil on success, otherwise the reason,
    /// so the screen can offer manual entry instead of just showing a dead end.
    func fetchReading(for profile: WatchedProfile) async -> String? {
        guard let token = TokenStore.load() else {
            return "Nessun token salvato: la rilevazione automatica ha bisogno dell'API ufficiale. Puoi inserire i numeri a mano."
        }
        isWorking = true
        progressNote = "Chiedo i numeri di @\(profile.username)…"
        defer { isWorking = false; progressNote = nil }

        let client = GraphAPIClient(token: token)
        do {
            if profile.isSelf {
                let me = try await client.profile()
                recordReading(followers: me.followersCount,
                              following: me.followsCount,
                              posts: me.mediaCount,
                              source: .businessDiscovery,
                              for: profile)
                return nil
            }
            let found = try await client.businessDiscovery(username: profile.username)
            guard found.followersCount != nil || found.followsCount != nil else {
                return "L'API non ha restituito numeri per @\(profile.username)."
            }
            recordReading(followers: found.followersCount,
                          following: found.followsCount,
                          posts: found.mediaCount,
                          source: .businessDiscovery,
                          for: profile)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Data management

    func deleteSnapshot(_ snapshot: Snapshot) {
        store.delete(snapshot)
        snapshots = store.snapshots
    }

    func deleteEverything() {
        store.deleteAll()
        AnalysisArchive.clear()
        watchlist.deleteAll()
        watched = []
        snapshots = []
        result = nil
        index = ProfileIndex()
        graphProfile = nil
        graphMedia = []
        graphInsights = []
    }
}
