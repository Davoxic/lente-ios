import Foundation

/// Last-resort input: paste or open a plain list of handles.
/// Accepts one per line, commas, spaces, `@` prefixes and full profile URLs,
/// because people paste whatever they have.
enum ManualImport {

    static func handles(from text: String) -> [String] {
        // Deliberately not splitting on spaces: a pasted sentence would otherwise
        // turn each of its words into a plausible-looking handle.
        let separators = CharacterSet(charactersIn: ",;\n\r\t")
        var seen = Set<String>()
        var out: [String] = []

        for rawToken in text.components(separatedBy: separators) {
            guard let handle = normalise(rawToken) else { continue }
            if seen.insert(handle.lowercased()).inserted { out.append(handle) }
        }
        return out
    }

    static func normalise(_ raw: String) -> String? {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }

        if token.lowercased().hasPrefix("http") {
            if let handle = ExportParser.username(fromProfileHref: token) { return handle }
            return nil
        }
        if token.hasPrefix("@") { token.removeFirst() }
        // Trailing punctuation from pasted lists.
        while let last = token.last, last == "." || last == "," || last == "/" {
            token.removeLast()
        }
        token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ExportParser.isHandle(token) else { return nil }
        return token
    }

    static func contents(followers: String, following: String) -> ExportContents {
        var out = ExportContents()
        out.followers = handles(from: followers).map { Account(username: $0) }
        out.following = handles(from: following).map { Account(username: $0) }
        if out.followers.isEmpty && out.following.isEmpty {
            out.warnings.append("Nessun nome utente riconosciuto nel testo incollato.")
        } else {
            out.warnings.append("Dati inseriti a mano: senza date non c'è grafico di crescita storico, ma gli snapshot successivi vengono confrontati tra loro.")
        }
        return out
    }
}
