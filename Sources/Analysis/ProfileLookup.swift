import Foundation

/// Everything the export knows about one account, gathered in one place so a
/// search can answer "qual è la mia situazione con questa persona" instantly.
///
/// The index only ever contains accounts that already appear in the owner's own
/// data. There is no lookup of arbitrary profiles: for anything beyond this,
/// the app opens the real Instagram profile, where the owner is signed in.
struct ProfileCard: Codable, Identifiable, Hashable {
    var username: String
    var followsYou: Bool = false
    var youFollow: Bool = false
    var followedYouSince: Date?
    var youFollowedSince: Date?
    var likesGiven: Int = 0
    var commentsGiven: Int = 0
    var isCloseFriend: Bool = false
    var isBlocked: Bool = false
    var isRestricted: Bool = false
    var isHidden: Bool = false
    var pendingRequestSent: Bool = false
    var requestReceived: Bool = false
    var recentlyUnfollowed: Bool = false

    var id: String { username }

    var interactions: Int { likesGiven + commentsGiven }

    enum Relationship: String, Codable {
        case mutual
        case onlyTheyFollow
        case onlyYouFollow
        case none

        var label: String {
            switch self {
            case .mutual: return "Vi seguite a vicenda"
            case .onlyTheyFollow: return "Ti segue, non lo segui"
            case .onlyYouFollow: return "Lo segui, non ti segue"
            case .none: return "Nessun follow tra voi"
            }
        }

        var symbol: String {
            switch self {
            case .mutual: return "arrow.left.arrow.right"
            case .onlyTheyFollow: return "heart"
            case .onlyYouFollow: return "arrow.uturn.left"
            case .none: return "person"
            }
        }
    }

    var relationship: Relationship {
        switch (youFollow, followsYou) {
        case (true, true): return .mutual
        case (false, true): return .onlyTheyFollow
        case (true, false): return .onlyYouFollow
        case (false, false): return .none
        }
    }

    /// Opens the profile in the Instagram app when it is installed.
    var appURL: URL? { URL(string: "instagram://user?username=\(username)") }
    var webURL: URL? { URL(string: "https://www.instagram.com/\(username)/") }
}

struct ProfileIndex: Codable {
    private(set) var cards: [String: ProfileCard] = [:]

    init() {}

    init(_ contents: ExportContents) {
        func touch(_ username: String, _ change: (inout ProfileCard) -> Void) {
            let key = username.lowercased()
            guard !key.isEmpty else { return }
            var card = cards[key] ?? ProfileCard(username: username)
            // Keep the first spelling seen; handles are case-insensitive.
            change(&card)
            cards[key] = card
        }

        for account in contents.followers {
            touch(account.username) { card in
                card.followsYou = true
                if card.followedYouSince == nil { card.followedYouSince = account.since }
            }
        }
        for account in contents.following {
            touch(account.username) { card in
                card.youFollow = true
                if card.youFollowedSince == nil { card.youFollowedSince = account.since }
            }
        }
        for account in contents.closeFriends {
            touch(account.username) { $0.isCloseFriend = true }
        }
        for account in contents.blocked {
            touch(account.username) { $0.isBlocked = true }
        }
        for account in contents.restricted {
            touch(account.username) { $0.isRestricted = true }
        }
        for account in contents.hidden {
            touch(account.username) { $0.isHidden = true }
        }
        for account in contents.pendingSent {
            touch(account.username) { $0.pendingRequestSent = true }
        }
        for account in contents.requestsReceived {
            touch(account.username) { $0.requestReceived = true }
        }
        for account in contents.recentlyUnfollowed {
            touch(account.username) { $0.recentlyUnfollowed = true }
        }
        for event in contents.likeEvents where !event.target.isEmpty {
            touch(event.target) { $0.likesGiven += 1 }
        }
        for event in contents.commentEvents where !event.target.isEmpty {
            touch(event.target) { $0.commentsGiven += 1 }
        }
    }

    var count: Int { cards.count }
    var isEmpty: Bool { cards.isEmpty }

    func card(for username: String) -> ProfileCard? {
        cards[username.lowercased()]
    }

    /// Prefix matches first, then substring matches; ties broken by how much
    /// the owner interacts with the account, so familiar names surface first.
    func search(_ rawQuery: String, limit: Int = 40) -> [ProfileCard] {
        let query = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        guard !query.isEmpty else { return [] }

        var prefixHits: [ProfileCard] = []
        var substringHits: [ProfileCard] = []

        for (key, card) in cards {
            if key.hasPrefix(query) {
                prefixHits.append(card)
            } else if key.contains(query) {
                substringHits.append(card)
            }
        }

        func rank(_ lhs: ProfileCard, _ rhs: ProfileCard) -> Bool {
            if lhs.interactions != rhs.interactions { return lhs.interactions > rhs.interactions }
            if lhs.username.count != rhs.username.count { return lhs.username.count < rhs.username.count }
            return lhs.username.lowercased() < rhs.username.lowercased()
        }

        prefixHits.sort(by: rank)
        substringHits.sort(by: rank)

        var combined = prefixHits
        combined.append(contentsOf: substringHits)
        if combined.count > limit {
            combined = Array(combined.prefix(limit))
        }
        return combined
    }

    /// Shown before the user types anything: the accounts they deal with most.
    func suggestions(limit: Int = 12) -> [ProfileCard] {
        var items: [ProfileCard] = []
        items.reserveCapacity(cards.count)
        for (_, card) in cards where card.interactions > 0 {
            items.append(card)
        }
        items.sort { (lhs: ProfileCard, rhs: ProfileCard) -> Bool in
            if lhs.interactions != rhs.interactions { return lhs.interactions > rhs.interactions }
            return lhs.username.lowercased() < rhs.username.lowercased()
        }
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
        return items
    }
}
