import Foundation

// MARK: - Account

struct Account: Codable, Hashable, Identifiable {
    var username: String
    var profileURL: String?
    /// When the relationship was created, where the export provides it.
    var since: Date?

    var id: String { username }

    var displayHandle: String { "@" + username }

    var resolvedURL: URL? {
        if let profileURL, let url = URL(string: profileURL) { return url }
        return URL(string: "https://www.instagram.com/\(username)/")
    }
}

// MARK: - Counted values

struct CountedAccount: Codable, Hashable, Identifiable {
    var username: String
    var count: Int
    var id: String { username }
}

struct TimeBucket: Codable, Hashable, Identifiable {
    /// First instant of the bucket (month granularity).
    var date: Date
    var count: Int
    var id: Date { date }
}

// MARK: - Raw material pulled out of an export

struct ExportContents {
    var followers: [Account] = []
    var following: [Account] = []
    var pendingSent: [Account] = []
    var requestsReceived: [Account] = []
    var recentlyUnfollowed: [Account] = []
    var closeFriends: [Account] = []
    var blocked: [Account] = []
    var restricted: [Account] = []
    var hidden: [Account] = []

    /// Outgoing engagement: accounts whose content you liked / commented on.
    var likeEvents: [EngagementEvent] = []
    var commentEvents: [EngagementEvent] = []

    /// Timestamps of your own published media.
    var ownPostDates: [Date] = []
    var ownStoryDates: [Date] = []
    var ownReelDates: [Date] = []

    var accountName: String?
    var username: String?
    var warnings: [String] = []

    var isEmpty: Bool {
        followers.isEmpty && following.isEmpty && likeEvents.isEmpty
            && commentEvents.isEmpty && ownPostDates.isEmpty
    }
}

struct EngagementEvent: Codable, Hashable {
    var target: String
    var date: Date?
}

// MARK: - Snapshot

/// A compact, persisted record of one import, so later imports can be diffed against it.
struct Snapshot: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var source: SourceKind = .dataExport
    var followers: [String] = []
    var following: [String] = []
    var label: String?

    enum SourceKind: String, Codable {
        case dataExport
        case graphAPI
        case manual

        var label: String {
            switch self {
            case .dataExport: return "Export dati"
            case .graphAPI: return "API ufficiale"
            case .manual: return "Manuale"
            }
        }
    }

    var followerCount: Int { followers.count }
    var followingCount: Int { following.count }
}

struct SnapshotDiff {
    var previous: Snapshot
    var current: Snapshot
    var gainedFollowers: [String]
    var lostFollowers: [String]
    var startedFollowing: [String]
    var stoppedFollowing: [String]

    var netFollowers: Int { gainedFollowers.count - lostFollowers.count }

    var interval: DateInterval {
        DateInterval(start: min(previous.createdAt, current.createdAt),
                     end: max(previous.createdAt, current.createdAt))
    }
}

// MARK: - Analysis

struct AnalysisResult: Codable {
    var generatedAt: Date = Date()
    var source: Snapshot.SourceKind = .dataExport
    var username: String?

    var followerCount: Int = 0
    var followingCount: Int = 0

    var mutuals: [Account] = []
    var notFollowingBack: [Account] = []
    var fans: [Account] = []
    var pendingSent: [Account] = []
    var requestsReceived: [Account] = []
    var recentlyUnfollowed: [Account] = []
    var closeFriends: [Account] = []
    var blocked: [Account] = []

    /// Accounts you engage with a lot that do not follow you back.
    var oneWayAttention: [CountedAccount] = []
    var topLiked: [CountedAccount] = []
    var topCommented: [CountedAccount] = []
    /// Followers you have never liked or commented on.
    var silentTowards: [Account] = []

    var followerGrowth: [TimeBucket] = []
    var followingGrowth: [TimeBucket] = []
    var likesByMonth: [TimeBucket] = []
    var ownPostsByMonth: [TimeBucket] = []

    /// 24 slots, local hours, from your own published media.
    var postingByHour: [Int] = Array(repeating: 0, count: 24)
    /// 7 slots, 0 = Sunday, matching Calendar's weekday component - 1.
    var postingByWeekday: [Int] = Array(repeating: 0, count: 7)

    var warnings: [String] = []

    var reciprocityRate: Double {
        guard followingCount > 0 else { return 0 }
        return Double(mutuals.count) / Double(followingCount)
    }

    var followerToFollowingRatio: Double {
        guard followingCount > 0 else { return 0 }
        return Double(followerCount) / Double(followingCount)
    }

    var bestHour: Int? {
        guard let maximum = postingByHour.max(), maximum > 0 else { return nil }
        return postingByHour.firstIndex(of: maximum)
    }

    var bestWeekday: Int? {
        guard let maximum = postingByWeekday.max(), maximum > 0 else { return nil }
        return postingByWeekday.firstIndex(of: maximum)
    }
}
