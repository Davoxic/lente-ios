import Foundation

/// One recorded observation of a profile's public counters.
struct ProfileReading: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var followers: Int?
    var following: Int?
    var posts: Int?
    var source: Source = .manual

    enum Source: String, Codable {
        case manual
        case businessDiscovery
        case ownExport

        var label: String {
            switch self {
            case .manual: return "A mano"
            case .businessDiscovery: return "API ufficiale"
            case .ownExport: return "Export"
            }
        }

        var symbol: String {
            switch self {
            case .manual: return "square.and.pencil"
            case .businessDiscovery: return "antenna.radiowaves.left.and.right"
            case .ownExport: return "shippingbox"
            }
        }
    }
}

/// A profile the owner has chosen to keep an eye on.
///
/// For any account other than the owner's, only the public counters are ever
/// recorded. The member lists of someone else's account are not obtainable
/// through anything official, and this app does not go around that.
struct WatchedProfile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var username: String
    var note: String?
    var isSelf: Bool = false
    var addedAt: Date = Date()
    var readings: [ProfileReading] = []

    var sortedReadings: [ProfileReading] {
        readings.sorted { $0.date < $1.date }
    }

    var latest: ProfileReading? { sortedReadings.last }

    var previous: ProfileReading? {
        let all = sortedReadings
        guard all.count >= 2 else { return nil }
        return all[all.count - 2]
    }

    /// Change in followers between the last two readings.
    var followerDelta: Int? {
        guard let latest, let previous,
              let now = latest.followers, let before = previous.followers else { return nil }
        return now - before
    }

    var followingDelta: Int? {
        guard let latest, let previous,
              let now = latest.following, let before = previous.following else { return nil }
        return now - before
    }

    /// Followers per day since the first reading, when there is enough history.
    var dailyRate: Double? {
        let all = sortedReadings
        guard let first = all.first, let last = all.last,
              let start = first.followers, let end = last.followers else { return nil }
        let days = last.date.timeIntervalSince(first.date) / 86_400
        guard days >= 1 else { return nil }
        return Double(end - start) / days
    }

    var followerSeries: [TimeBucket] {
        var out: [TimeBucket] = []
        for reading in sortedReadings {
            guard let followers = reading.followers else { continue }
            out.append(TimeBucket(date: reading.date, count: followers))
        }
        return out
    }

    var followingSeries: [TimeBucket] {
        var out: [TimeBucket] = []
        for reading in sortedReadings {
            guard let following = reading.following else { continue }
            out.append(TimeBucket(date: reading.date, count: following))
        }
        return out
    }

    var appURL: URL? { URL(string: "instagram://user?username=\(username)") }
    var webURL: URL? { URL(string: "https://www.instagram.com/\(username)/") }
}

/// Watchlist persistence. Plain JSON in the app's Documents folder.
final class WatchlistStore {
    private let url: URL
    private(set) var profiles: [WatchedProfile] = []

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.url = base.appendingPathComponent("watchlist.json")
        load()
    }

    func add(username: String, isSelf: Bool = false) -> WatchedProfile? {
        guard let handle = ManualImport.normalise(username) else { return nil }
        let key = handle.lowercased()
        if let existing = profiles.first(where: { $0.username.lowercased() == key }) {
            return existing
        }
        let profile = WatchedProfile(username: handle, isSelf: isSelf)
        profiles.append(profile)
        save()
        return profile
    }

    func remove(_ profile: WatchedProfile) {
        profiles.removeAll { $0.id == profile.id }
        save()
    }

    func record(_ reading: ProfileReading, for profileID: UUID) {
        guard let position = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[position].readings.append(reading)
        save()
    }

    func deleteReading(_ readingID: UUID, from profileID: UUID) {
        guard let position = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[position].readings.removeAll { $0.id == readingID }
        save()
    }

    func updateNote(_ note: String?, for profileID: UUID) {
        guard let position = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[position].note = note
        save()
    }

    func profile(with id: UUID) -> WatchedProfile? {
        profiles.first { $0.id == id }
    }

    func deleteAll() {
        profiles = []
        save()
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([WatchedProfile].self, from: data) {
            profiles = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(profiles) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
