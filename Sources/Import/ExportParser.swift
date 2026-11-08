import Foundation

/// Reads an Instagram "Download your information" archive.
///
/// The export layout and the JSON key names have changed several times and are
/// partly localised to the account language, so nothing here depends on a fixed
/// path: files are located by name anywhere in the archive and the JSON is walked
/// tolerantly. Anything that cannot be understood is reported as a warning instead
/// of failing the whole import.
struct ExportParser {

    static func parse(archiveAt url: URL) throws -> ExportContents {
        let archive = try ZipArchive(url: url)
        return parse(archive: archive)
    }

    static func parse(archive: ZipArchive) -> ExportContents {
        var out = ExportContents()

        let files = archive.entries.filter { !$0.isDirectory }
        let jsonFiles = files.filter { $0.fileName.hasSuffix(".json") }

        if jsonFiles.isEmpty {
            if files.contains(where: { $0.fileName.hasSuffix(".html") }) {
                out.warnings.append("L'archivio contiene solo HTML. Richiedi di nuovo l'export scegliendo il formato JSON.")
            } else {
                out.warnings.append("Nessun file JSON trovato nell'archivio.")
            }
            return out
        }

        func load(_ entry: ZipEntry) -> Data? {
            do { return try archive.data(for: entry) } catch {
                out.warnings.append("Non ho potuto leggere \(entry.path).")
                return nil
            }
        }

        func relationships(matching test: (String) -> Bool) -> [Account] {
            var seen = Set<String>()
            var accounts: [Account] = []
            for entry in jsonFiles where test(entry.fileName) {
                guard let data = load(entry) else { continue }
                for record in Self.records(from: data) {
                    guard let account = Self.relationshipAccount(from: record) else { continue }
                    let key = account.username.lowercased()
                    if seen.insert(key).inserted { accounts.append(account) }
                }
            }
            return accounts
        }

        out.followers = relationships { Self.matchesNumbered($0, base: "followers") }
        out.following = relationships { Self.matchesNumbered($0, base: "following") }
        out.pendingSent = relationships {
            $0.contains("pending_follow_request") || $0.contains("follow_requests_sent")
        }
        out.requestsReceived = relationships {
            $0.contains("follow_request") && $0.contains("receiv")
        }
        out.recentlyUnfollowed = relationships { $0.contains("recently_unfollowed") }
        out.closeFriends = relationships { $0.contains("close_friends") }
        out.blocked = relationships { $0.contains("blocked") }
        out.restricted = relationships { $0.contains("restricted") }
        out.hidden = relationships { $0.contains("hide_stories") || $0.contains("hidden_stories") }

        // Outgoing engagement.
        for entry in jsonFiles where Self.isLikeFile(entry.fileName) {
            guard let data = load(entry) else { continue }
            out.likeEvents.append(contentsOf: Self.engagementEvents(from: data))
        }

        for entry in jsonFiles where Self.isCommentFile(entry.fileName) {
            guard let data = load(entry) else { continue }
            out.commentEvents.append(contentsOf: Self.engagementEvents(from: data))
        }

        // Your own media timestamps.
        for entry in jsonFiles {
            let name = entry.fileName
            if Self.matchesNumbered(name, base: "posts") {
                guard let data = load(entry) else { continue }
                out.ownPostDates.append(contentsOf: Self.allDates(in: data))
            } else if name == "stories.json" {
                guard let data = load(entry) else { continue }
                out.ownStoryDates.append(contentsOf: Self.allDates(in: data))
            } else if name == "reels.json" || name == "ig_reels.json" {
                guard let data = load(entry) else { continue }
                out.ownReelDates.append(contentsOf: Self.allDates(in: data))
            }
        }

        // Account identity, best effort.
        for entry in jsonFiles where Self.isIdentityFile(entry.fileName) {
            guard let data = load(entry) else { continue }
            if let identity = Self.identity(from: data) {
                out.username = out.username ?? identity.username
                out.accountName = out.accountName ?? identity.name
            }
        }

        if out.followers.isEmpty && out.following.isEmpty {
            out.warnings.append("Nell'archivio non ho trovato le liste follower/seguiti. Controlla di aver richiesto la categoria \"Follower e seguiti\".")
        }

        return out
    }

    // MARK: - File name matching

    /// Matches `base.json`, `base_1.json`, `base_2.json`, ... but not `liked_base.json`.
    private static func matchesNumbered(_ fileName: String, base: String) -> Bool {
        guard fileName.hasSuffix(".json") else { return false }
        let stem = String(fileName.dropLast(5))
        if stem == base { return true }
        guard stem.hasPrefix(base + "_") else { return false }
        let suffix = stem.dropFirst(base.count + 1)
        return !suffix.isEmpty && suffix.allSatisfy { $0.isNumber }
    }

    private static func isLikeFile(_ fileName: String) -> Bool {
        guard fileName.hasSuffix(".json") else { return false }
        if fileName.contains("liked_posts") { return true }
        if fileName.contains("liked_comments") { return true }
        if fileName.contains("story_likes") { return true }
        return false
    }

    private static func isIdentityFile(_ fileName: String) -> Bool {
        guard fileName.hasSuffix(".json") else { return false }
        return fileName.contains("personal_information")
            || fileName.contains("account_information")
    }

    private static func isCommentFile(_ fileName: String) -> Bool {
        guard fileName.hasSuffix(".json"), fileName.contains("comment") else { return false }
        if fileName.contains("liked") { return false }
        return fileName.contains("post_comments")
            || fileName.contains("reels_comments")
            || fileName.contains("media_comments")
    }

    // MARK: - JSON shaping

    /// Known container keys, tried before falling back to the longest array found.
    private static let containerKeys = [
        "relationships_followers", "relationships_following",
        "relationships_follow_requests_sent", "relationships_permanent_follow_requests",
        "relationships_unfollowed_users", "relationships_close_friends",
        "relationships_blocked_users", "relationships_restricted_users",
        "relationships_hide_stories_from", "relationships_follow_requests_received",
        "likes_media_likes", "likes_comment_likes", "story_activities_story_likes",
        "comments_media_comments", "comments_reels_comments",
        "ig_stories", "ig_reels_media", "ig_posts"
    ]

    static func records(from data: Data) -> [[String: Any]] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let array = root as? [[String: Any]] { return array }
        guard let dictionary = root as? [String: Any] else { return [] }

        for key in containerKeys {
            if let array = dictionary[key] as? [[String: Any]] { return array }
        }
        // Deterministic fallback: the longest array of objects anywhere at this level.
        var best: [[String: Any]] = []
        for key in dictionary.keys.sorted() {
            if let array = dictionary[key] as? [[String: Any]], array.count > best.count {
                best = array
            }
        }
        if !best.isEmpty { return best }

        // Some files nest one more level, e.g. { "ig_other_media": { "media": [...] } }.
        for key in dictionary.keys.sorted() {
            if let nested = dictionary[key] as? [String: Any] {
                for innerKey in nested.keys.sorted() {
                    if let array = nested[innerKey] as? [[String: Any]], array.count > best.count {
                        best = array
                    }
                }
            }
        }
        return best
    }

    // MARK: - Accounts

    private static let reservedPathComponents: Set<String> = [
        "p", "reel", "reels", "tv", "stories", "explore", "s", "accounts", "direct"
    ]

    static func relationshipAccount(from record: [String: Any]) -> Account? {
        guard let list = record["string_list_data"] as? [[String: Any]], let first = list.first else {
            // Newer map-style record.
            if let map = record["string_map_data"] as? [String: Any] {
                for key in map.keys.sorted() {
                    if let leaf = map[key] as? [String: Any],
                       let value = leaf["value"] as? String,
                       isHandle(value) {
                        return Account(username: value, profileURL: nil, since: date(from: leaf["timestamp"]))
                    }
                }
            }
            return nil
        }

        let href = first["href"] as? String
        let value = (first["value"] as? String).flatMap(nonEmpty)
        let when = date(from: first["timestamp"])

        if let handle = username(fromProfileHref: href) {
            return Account(username: handle, profileURL: href, since: when)
        }
        if let value, isHandle(value) {
            return Account(username: value, profileURL: href, since: when)
        }
        if let title = (record["title"] as? String).flatMap(nonEmpty), isHandle(title) {
            return Account(username: title, profileURL: href, since: when)
        }
        return nil
    }

    static func username(fromProfileHref href: String?) -> String? {
        guard let href, let url = URL(string: href) else { return nil }
        guard let host = url.host?.lowercased(), host.contains("instagram.com") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let first = parts.first else { return nil }
        let candidate = first.lowercased()
        guard !reservedPathComponents.contains(candidate) else { return nil }
        guard isHandle(first) else { return nil }
        return first
    }

    static func isHandle(_ candidate: String) -> Bool {
        guard !candidate.isEmpty, candidate.count <= 30 else { return false }
        return candidate.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "_")
        }
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Engagement

    static func engagementEvents(from data: Data) -> [EngagementEvent] {
        var events: [EngagementEvent] = []
        for record in records(from: data) {
            let title = (record["title"] as? String).flatMap(nonEmpty)
            var when: Date?

            if let list = record["string_list_data"] as? [[String: Any]], let first = list.first {
                when = date(from: first["timestamp"])
            }
            if when == nil, let map = record["string_map_data"] as? [String: Any] {
                for key in map.keys.sorted() {
                    if let leaf = map[key] as? [String: Any], let found = date(from: leaf["timestamp"]) {
                        when = found
                        break
                    }
                }
            }
            if when == nil { when = date(from: record["timestamp"]) }

            // A target is only recorded when it is unambiguously a handle, so the
            // "who you engage with most" figures never contain guessed names.
            let target = (title.flatMap { isHandle($0) ? $0 : nil }) ?? ""
            if target.isEmpty && when == nil { continue }
            events.append(EngagementEvent(target: target, date: when))
        }
        return events
    }

    // MARK: - Dates

    static func allDates(in data: Data) -> [Date] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var dates: [Date] = []
        collectDates(root, into: &dates)
        return dates
    }

    private static let dateKeys: Set<String> = [
        "creation_timestamp", "taken_at", "timestamp", "last_modified_timestamp"
    ]

    private static func collectDates(_ node: Any, into dates: inout [Date]) {
        if let dictionary = node as? [String: Any] {
            for (key, value) in dictionary {
                if dateKeys.contains(key), let found = date(from: value) {
                    dates.append(found)
                } else {
                    collectDates(value, into: &dates)
                }
            }
        } else if let array = node as? [Any] {
            for element in array { collectDates(element, into: &dates) }
        }
    }

    /// Export timestamps are Unix seconds. Values outside a sane window are discarded
    /// so that millisecond values or placeholders never land in a chart.
    static func date(from value: Any?) -> Date? {
        var seconds: Double?
        if let number = value as? NSNumber { seconds = number.doubleValue }
        else if let text = value as? String, let parsed = Double(text) { seconds = parsed }
        guard var raw = seconds else { return nil }
        if raw > 100_000_000_000 { raw /= 1000 }   // tolerate milliseconds
        guard raw > 1_000_000_000, raw < 4_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    // MARK: - Identity

    private static func identity(from data: Data) -> (username: String?, name: String?)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var username: String?
        var name: String?
        scanIdentity(root, username: &username, name: &name)
        if username == nil && name == nil { return nil }
        return (username, name)
    }

    private static func scanIdentity(_ node: Any, username: inout String?, name: inout String?) {
        if let dictionary = node as? [String: Any] {
            for (key, value) in dictionary {
                let lowered = key.lowercased()
                if let leaf = value as? [String: Any], let text = leaf["value"] as? String {
                    if username == nil, lowered.contains("username") || lowered.contains("nome utente") {
                        username = isHandle(text) ? text : nil
                    }
                    if name == nil, lowered == "name" || lowered.contains("nome") {
                        name = Mojibake.repaired(text)
                    }
                }
                scanIdentity(value, username: &username, name: &name)
            }
        } else if let array = node as? [Any] {
            for element in array { scanIdentity(element, username: &username, name: &name) }
        }
    }
}

// MARK: - Mojibake

/// Instagram exports write UTF-8 bytes escaped as Latin-1 code points, which turns
/// accented names into mush. This reverses that when it is safe to do so.
enum Mojibake {
    static func repaired(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value >= 0x80 && $0.value <= 0xFF }) else {
            return text
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            guard scalar.value <= 0xFF else { return text }
            bytes.append(UInt8(scalar.value))
        }
        if let decoded = String(bytes: bytes, encoding: .utf8), !decoded.isEmpty {
            return decoded
        }
        return text
    }
}
