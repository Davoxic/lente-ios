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

    // Official API state
    @Published var graphProfile: GraphProfile?
    @Published var graphMedia: [GraphMedia] = []
    @Published var graphInsights: [GraphInsightValue] = []
    @Published var hasToken: Bool = TokenStore.hasToken

    private let store = SnapshotStore()

    init() {
        snapshots = store.snapshots
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
            let snapshot = Analyzer.snapshot(from: contents, source: .dataExport)
            store.append(snapshot)
            snapshots = store.snapshots
            result = analysis
            activeSource = .export
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
        let snapshot = Analyzer.snapshot(from: contents, source: .manual)
        store.append(snapshot)
        snapshots = store.snapshots
        result = analysis
        activeSource = .manual
        errorMessage = nil
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

    // MARK: - Data management

    func deleteSnapshot(_ snapshot: Snapshot) {
        store.delete(snapshot)
        snapshots = store.snapshots
    }

    func deleteEverything() {
        store.deleteAll()
        snapshots = []
        result = nil
        graphProfile = nil
        graphMedia = []
        graphInsights = []
    }
}
