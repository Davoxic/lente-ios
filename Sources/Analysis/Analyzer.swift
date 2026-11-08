import Foundation

/// Turns parsed export contents into the figures the app shows.
/// Everything here is derived arithmetic on data the account owner already has;
/// nothing is inferred about other people beyond the relationships the export states.
struct Analyzer {

    static func analyze(_ contents: ExportContents,
                        source: Snapshot.SourceKind = .dataExport) -> AnalysisResult {
        var result = AnalysisResult()
        result.source = source
        result.username = contents.username
        result.warnings = contents.warnings

        let followerIndex = index(contents.followers)
        let followingIndex = index(contents.following)
        let followerKeys = Set(followerIndex.keys)
        let followingKeys = Set(followingIndex.keys)

        result.followerCount = followerIndex.count
        result.followingCount = followingIndex.count

        result.mutuals = sortedAccounts(followingKeys.intersection(followerKeys), followingIndex)
        result.notFollowingBack = sortedAccounts(followingKeys.subtracting(followerKeys), followingIndex)
        result.fans = sortedAccounts(followerKeys.subtracting(followingKeys), followerIndex)

        result.pendingSent = contents.pendingSent.sorted { $0.username < $1.username }
        result.requestsReceived = contents.requestsReceived.sorted { $0.username < $1.username }
        result.recentlyUnfollowed = contents.recentlyUnfollowed.sorted { lhs, rhs in
            switch (lhs.since, rhs.since) {
            case let (left?, right?): return left > right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.username < rhs.username
            }
        }
        result.closeFriends = contents.closeFriends.sorted { $0.username < $1.username }
        result.blocked = contents.blocked.sorted { $0.username < $1.username }

        // Growth, from the dates the export attaches to each relationship.
        result.followerGrowth = cumulativeByMonth(contents.followers.compactMap(\.since))
        result.followingGrowth = cumulativeByMonth(contents.following.compactMap(\.since))

        // Your own outgoing activity.
        result.likesByMonth = countByMonth(contents.likeEvents.compactMap(\.date))
        let ownMedia = contents.ownPostDates + contents.ownReelDates
        result.ownPostsByMonth = countByMonth(ownMedia)

        var byHour = Array(repeating: 0, count: 24)
        var byWeekday = Array(repeating: 0, count: 7)
        var calendar = Calendar.current
        calendar.timeZone = .current
        for date in ownMedia {
            let components = calendar.dateComponents([.hour, .weekday], from: date)
            if let hour = components.hour, hour >= 0, hour < 24 { byHour[hour] += 1 }
            if let weekday = components.weekday, weekday >= 1, weekday <= 7 { byWeekday[weekday - 1] += 1 }
        }
        result.postingByHour = byHour
        result.postingByWeekday = byWeekday

        // Who you give attention to.
        let likeCounts = tally(contents.likeEvents)
        let commentCounts = tally(contents.commentEvents)
        result.topLiked = ranked(likeCounts, limit: 50)
        result.topCommented = ranked(commentCounts, limit: 50)

        var combined = likeCounts
        for (key, value) in commentCounts { combined[key, default: 0] += value }

        result.oneWayAttention = ranked(combined.filter { !followerKeys.contains($0.key) }, limit: 50)

        if !combined.isEmpty {
            let engaged = Set(combined.keys)
            let silentKeys = followerKeys.subtracting(engaged)
            result.silentTowards = sortedAccounts(silentKeys, followerIndex)
        }

        if contents.likeEvents.isEmpty && contents.commentEvents.isEmpty {
            result.warnings.append("Nessun dato di like o commenti nell'archivio: le metriche di interazione restano vuote. Richiedi anche la categoria \"La tua attività su Instagram\".")
        }
        if contents.followers.allSatisfy({ $0.since == nil }) && !contents.followers.isEmpty {
            result.warnings.append("L'export non riporta le date dei follower, quindi il grafico di crescita parte dal primo snapshot salvato qui.")
        }

        return result
    }

    // MARK: - Snapshots

    static func snapshot(from contents: ExportContents,
                         source: Snapshot.SourceKind = .dataExport) -> Snapshot {
        Snapshot(createdAt: Date(),
                 source: source,
                 followers: contents.followers.map { $0.username.lowercased() }.sorted(),
                 following: contents.following.map { $0.username.lowercased() }.sorted())
    }

    static func diff(previous: Snapshot, current: Snapshot) -> SnapshotDiff {
        let previousFollowers = Set(previous.followers)
        let currentFollowers = Set(current.followers)
        let previousFollowing = Set(previous.following)
        let currentFollowing = Set(current.following)

        return SnapshotDiff(
            previous: previous,
            current: current,
            gainedFollowers: currentFollowers.subtracting(previousFollowers).sorted(),
            lostFollowers: previousFollowers.subtracting(currentFollowers).sorted(),
            startedFollowing: currentFollowing.subtracting(previousFollowing).sorted(),
            stoppedFollowing: previousFollowing.subtracting(currentFollowing).sorted()
        )
    }

    // MARK: - Helpers

    private static func index(_ accounts: [Account]) -> [String: Account] {
        var map: [String: Account] = [:]
        map.reserveCapacity(accounts.count)
        for account in accounts {
            let key = account.username.lowercased()
            if let existing = map[key] {
                // Keep whichever record carries a date.
                if existing.since == nil, account.since != nil { map[key] = account }
            } else {
                map[key] = account
            }
        }
        return map
    }

    private static func sortedAccounts(_ keys: Set<String>, _ index: [String: Account]) -> [Account] {
        keys.compactMap { index[$0] }.sorted { $0.username.lowercased() < $1.username.lowercased() }
    }

    private static func tally(_ events: [EngagementEvent]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for event in events where !event.target.isEmpty {
            counts[event.target.lowercased(), default: 0] += 1
        }
        return counts
    }

    private static func ranked(_ counts: [String: Int], limit: Int) -> [CountedAccount] {
        counts.map { CountedAccount(username: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.username < rhs.username : lhs.count > rhs.count
            }
            .prefix(limit)
            .map { $0 }
    }

    static func monthStart(_ date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    static func countByMonth(_ dates: [Date]) -> [TimeBucket] {
        guard !dates.isEmpty else { return [] }
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for date in dates {
            counts[monthStart(date, calendar: calendar), default: 0] += 1
        }
        return counts.keys.sorted().map { TimeBucket(date: $0, count: counts[$0] ?? 0) }
    }

    /// Running total per month, so the chart reads as a growth curve rather than
    /// a bar chart of joins.
    static func cumulativeByMonth(_ dates: [Date]) -> [TimeBucket] {
        let monthly = countByMonth(dates)
        guard !monthly.isEmpty else { return [] }
        var running = 0
        var buckets: [TimeBucket] = []
        buckets.reserveCapacity(monthly.count)
        for bucket in monthly {
            running += bucket.count
            buckets.append(TimeBucket(date: bucket.date, count: running))
        }
        return buckets
    }
}
