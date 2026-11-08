import SwiftUI

@MainActor
struct Card<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            content
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

@MainActor
struct StatTile: View {
    var value: String
    var label: String
    var systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

@MainActor
struct AccountRow: View {
    var username: String
    var detail: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                Text(initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("@" + username)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let trailing {
                Text(trailing)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var initials: String {
        let letters = username.filter { $0.isLetter || $0.isNumber }
        return String(letters.prefix(2)).uppercased()
    }
}

/// A list of accounts that can be searched, opened in the browser and exported.
@MainActor
struct AccountListScreen: View {
    var title: String
    var explanation: String
    var accounts: [Account]
    var counts: [String: Int] = [:]

    @State private var query = ""

    private var filtered: [Account] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return accounts }
        return accounts.filter { $0.username.lowercased().contains(trimmed) }
    }

    var body: some View {
        List {
            Section {
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("\(filtered.count) account") {
                if filtered.isEmpty {
                    Text("Nessun risultato.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { account in
                        rowLink(for: account)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Cerca")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(accounts.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func rowLink(for account: Account) -> some View {
        let trailing = counts[account.username.lowercased()].map { "\($0)" }
        if let url = account.resolvedURL {
            Link(destination: url) {
                AccountRow(username: account.username,
                           detail: Self.detail(for: account),
                           trailing: trailing)
            }
            .buttonStyle(.plain)
        } else {
            AccountRow(username: account.username,
                       detail: Self.detail(for: account),
                       trailing: trailing)
        }
    }

    private static func detail(for account: Account) -> String? {
        guard let since = account.since else { return nil }
        return "dal " + since.formatted(date: .abbreviated, time: .omitted)
    }

    private var shareText: String {
        accounts.map { "@" + $0.username }.joined(separator: "\n")
    }
}

@MainActor
struct EmptyState: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

extension Int {
    var grouped: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
