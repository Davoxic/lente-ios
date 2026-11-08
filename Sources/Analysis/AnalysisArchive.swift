import Foundation

/// Keeps the last analysis on disk so reopening the app does not mean
/// re-importing the archive. Same rule as everywhere else: usernames, counts
/// and dates only, in the app's own Documents folder.
struct PersistedAnalysis: Codable {
    var result: AnalysisResult
    var index: ProfileIndex
    var savedAt: Date
}

enum AnalysisArchive {
    private static var url: URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("last-analysis.json")
    }

    static func save(result: AnalysisResult, index: ProfileIndex) {
        let payload = PersistedAnalysis(result: result, index: index, savedAt: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> PersistedAnalysis? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistedAnalysis.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
