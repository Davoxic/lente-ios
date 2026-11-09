import Foundation

/// Parses the follower counts as Instagram actually shows them.
///
/// The app abbreviates above ten thousand ("12,5K", "1.2M"), and the thousands
/// separator differs by locale ("1.234" in Italian, "1,234" in English). Simply
/// stripping non-digits would read "12,5K" as 125, so the suffix is handled
/// first and separators only afterwards.
enum CountText {
    static func parse(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }

        let multipliers: [(String, Double)] = [
            ("mld", 1_000_000_000),
            ("mln", 1_000_000),
            ("bn", 1_000_000_000),
            ("b", 1_000_000_000),
            ("mila", 1_000),
            ("m", 1_000_000),
            ("k", 1_000)
        ]

        for (suffix, factor) in multipliers where text.hasSuffix(suffix) {
            let head = String(text.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespaces)
            guard let value = decimal(head) else { continue }
            return Int((value * factor).rounded())
        }

        // No suffix: every separator is a thousands separator.
        var digits = ""
        for character in text where character.isNumber {
            digits.append(character)
        }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    /// Reads "12,5" and "12.5" alike, rejecting anything with more than one
    /// separator (that would be a grouped number, not a decimal).
    private static func decimal(_ raw: String) -> Double? {
        var normalised = ""
        var separators = 0
        for character in raw {
            if character.isNumber {
                normalised.append(character)
            } else if character == "," || character == "." {
                separators += 1
                normalised.append(".")
            } else if character == " " {
                continue
            } else {
                return nil
            }
        }
        guard separators <= 1, !normalised.isEmpty else { return nil }
        return Double(normalised)
    }
}
