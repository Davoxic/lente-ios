import Foundation

/// Snapshots live in the app's Documents folder as a single JSON file.
/// Only usernames and counts are kept, never media, so the file stays small.
/// Nothing is uploaded anywhere.
final class SnapshotStore {
    static let fileName = "snapshots.json"

    private let url: URL
    private(set) var snapshots: [Snapshot] = []

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.url = base.appendingPathComponent(SnapshotStore.fileName)
        load()
    }

    var latest: Snapshot? { snapshots.last }

    var previous: Snapshot? {
        guard snapshots.count >= 2 else { return nil }
        return snapshots[snapshots.count - 2]
    }

    /// Diff of the two most recent snapshots, when there are two to compare.
    var latestDiff: SnapshotDiff? {
        guard let previous, let latest else { return nil }
        return Analyzer.diff(previous: previous, current: latest)
    }

    func append(_ snapshot: Snapshot) {
        snapshots.append(snapshot)
        snapshots.sort { $0.createdAt < $1.createdAt }
        // Keep a long but bounded history.
        if snapshots.count > 200 {
            snapshots.removeFirst(snapshots.count - 200)
        }
        save()
    }

    func delete(_ snapshot: Snapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        save()
    }

    func deleteAll() {
        snapshots.removeAll()
        save()
    }

    /// Growth curve assembled from stored snapshots, used when the export
    /// carries no per-follower dates.
    func followerSeries() -> [TimeBucket] {
        snapshots.map { TimeBucket(date: $0.createdAt, count: $0.followerCount) }
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Snapshot].self, from: data) {
            snapshots = decoded.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(snapshots) else { return }
        do {
            try data.write(to: url, options: .atomic)
            // Snapshots are personal: keep them out of iCloud/iTunes backups
            // only if the user asked for that via Settings; by default they are
            // backed up like any other document.
        } catch {
            // A failed write is not worth interrupting the session for; the
            // analysis in memory is still valid.
        }
    }
}
