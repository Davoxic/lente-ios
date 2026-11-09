import Foundation

// MARK: - Shapes

struct GraphProfile: Codable, Equatable {
    var id: String
    var username: String?
    var name: String?
    var followersCount: Int?
    var followsCount: Int?
    var mediaCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, name
        case followersCount = "followers_count"
        case followsCount = "follows_count"
        case mediaCount = "media_count"
    }
}

struct GraphMedia: Codable, Identifiable, Equatable {
    var id: String
    var caption: String?
    var mediaType: String?
    var permalink: String?
    var timestamp: String?
    var likeCount: Int?
    var commentsCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, caption, permalink, timestamp
        case mediaType = "media_type"
        case likeCount = "like_count"
        case commentsCount = "comments_count"
    }

    var date: Date? {
        guard let timestamp else { return nil }
        return GraphAPIClient.timestampFormatter.date(from: timestamp)
    }

    var engagement: Int { (likeCount ?? 0) + (commentsCount ?? 0) }
}

struct GraphInsightValue: Equatable {
    var name: String
    var title: String
    var total: Int
}


/// What the official Business Discovery endpoint returns about another account.
/// Note what is absent: there is no follower *list* here, and there is no way to
/// ask for one. Instagram does not expose the membership of anyone's follower
/// graph through any official endpoint.
struct DiscoveredProfile: Equatable {
    var username: String
    var name: String?
    var biography: String?
    var website: String?
    var followersCount: Int?
    var followsCount: Int?
    var mediaCount: Int?
}

enum GraphAPIError: LocalizedError {
    case missingToken
    case transport(String)
    case api(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Nessun token salvato. Incollalo nelle impostazioni."
        case .transport(let detail):
            return "Problema di rete: \(detail)"
        case .api(let message):
            return message
        case .decoding:
            return "Risposta dell'API non riconosciuta."
        }
    }
}

// MARK: - Client

/// Thin client for the official Instagram API (Instagram Login).
///
/// Two things worth knowing, both surfaced in the UI rather than hidden:
/// the official API never exposes the follower *list* - only counts - so the
/// reciprocity analysis is export-only; and the available insight metrics change
/// between API versions, so the metric set degrades gracefully instead of failing.
struct GraphAPIClient {
    var token: String
    var version: String = "v21.0"
    var host: String = "graph.instagram.com"

    static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Metric sets tried in order; the first one the API accepts is used.
    static let insightMetricSets: [[String]] = [
        ["reach", "views", "total_interactions", "accounts_engaged", "profile_views"],
        ["reach", "total_interactions", "profile_views"],
        ["reach", "impressions", "profile_views"],
        ["reach"]
    ]

    // MARK: Requests

    private func url(path: String, query: [String: String]) throws -> URL {
        guard !token.isEmpty else { throw GraphAPIError.missingToken }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/\(version)/\(path)"
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "access_token", value: token))
        components.queryItems = items.sorted { $0.name < $1.name }
        guard let url = components.url else { throw GraphAPIError.decoding }
        return url
    }

    private func fetch(path: String, query: [String: String]) async throws -> Data {
        let request = URLRequest(url: try url(path: path, query: query),
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 30)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GraphAPIError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw GraphAPIError.api(Self.message(from: data)
                ?? "L'API ha risposto \(http.statusCode).")
        }
        return data
    }

    private static func message(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return nil }
        let message = error["message"] as? String
        let type = error["type"] as? String
        if let message, let type { return "\(type): \(message)" }
        return message
    }

    // MARK: Endpoints

    func profile() async throws -> GraphProfile {
        let fields = "id,username,name,followers_count,follows_count,media_count"
        let data = try await fetch(path: "me", query: ["fields": fields])
        guard let profile = try? JSONDecoder().decode(GraphProfile.self, from: data) else {
            throw GraphAPIError.decoding
        }
        return profile
    }

    func media(limit: Int = 50) async throws -> [GraphMedia] {
        let fields = "id,caption,media_type,permalink,timestamp,like_count,comments_count"
        let data = try await fetch(path: "me/media",
                                   query: ["fields": fields, "limit": String(limit)])
        struct Envelope: Codable { let data: [GraphMedia] }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw GraphAPIError.decoding
        }
        return envelope.data
    }


    /// Public counters for another account, through the official Business
    /// Discovery endpoint. Works only when the caller's account is a professional
    /// one and the target is a public professional account; everything else comes
    /// back as an error the UI turns into "inseriscilo a mano".
    func businessDiscovery(username rawUsername: String) async throws -> DiscoveredProfile {
        let target = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard !target.isEmpty else { throw GraphAPIError.api("Nome utente vuoto.") }

        let inner = "username,name,biography,website,followers_count,follows_count,media_count"
        let field = "business_discovery.username(\(target)){\(inner)}"
        let data = try await fetch(path: "me", query: ["fields": field])

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let discovery = object["business_discovery"] as? [String: Any] else {
            throw GraphAPIError.api("L'API non ha restituito dati per @\(target). Succede se l'account è privato, personale, o se il tuo non è un account professionale.")
        }

        func number(_ key: String) -> Int? {
            (discovery[key] as? NSNumber)?.intValue
        }

        return DiscoveredProfile(
            username: (discovery["username"] as? String) ?? target,
            name: discovery["name"] as? String,
            biography: discovery["biography"] as? String,
            website: discovery["website"] as? String,
            followersCount: number("followers_count"),
            followsCount: number("follows_count"),
            mediaCount: number("media_count")
        )
    }

    /// Account insights for the last `days` days. Falls back through
    /// `insightMetricSets` because metric availability changes per API version.
    func accountInsights(days: Int = 28) async throws -> [GraphInsightValue] {
        let now = Date()
        let since = Int(now.addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970)
        let until = Int(now.timeIntervalSince1970)

        var lastError: Error = GraphAPIError.decoding
        for metrics in Self.insightMetricSets {
            do {
                let data = try await fetch(path: "me/insights", query: [
                    "metric": metrics.joined(separator: ","),
                    "period": "day",
                    "metric_type": "total_value",
                    "since": String(since),
                    "until": String(until)
                ])
                let parsed = Self.parseInsights(data)
                if !parsed.isEmpty { return parsed }
                lastError = GraphAPIError.decoding
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func parseInsights(_ data: Data) -> [GraphInsightValue] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["data"] as? [[String: Any]] else { return [] }

        var out: [GraphInsightValue] = []
        for row in rows {
            let name = (row["name"] as? String) ?? "metric"
            let title = (row["title"] as? String) ?? name
            var total = 0
            if let totalValue = row["total_value"] as? [String: Any],
               let value = totalValue["value"] as? NSNumber {
                total = value.intValue
            } else if let values = row["values"] as? [[String: Any]] {
                for entry in values {
                    if let value = entry["value"] as? NSNumber { total += value.intValue }
                }
            }
            out.append(GraphInsightValue(name: name, title: title, total: total))
        }
        return out
    }
}
