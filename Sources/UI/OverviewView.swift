import SwiftUI
import Charts

@MainActor
struct OverviewView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let result = state.result {
                        exportSummary(result)
                    }
                    if state.graphProfile != nil {
                        apiSummary()
                    }
                    if !state.hasData {
                        EmptyState(title: "Nessun dato ancora",
                                   message: "Vai in Dati e importa l'export del tuo account. Se non ce l'hai, puoi usare l'API ufficiale o incollare le liste a mano.",
                                   systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Panoramica")
        }
    }

    // MARK: - Export

    @ViewBuilder
    private func exportSummary(_ result: AnalysisResult) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]

        LazyVGrid(columns: columns, spacing: 12) {
            StatTile(value: result.followerCount.grouped,
                     label: "Follower",
                     systemImage: "person.2.fill")
            StatTile(value: result.followingCount.grouped,
                     label: "Seguiti",
                     systemImage: "person.badge.plus")
            StatTile(value: result.notFollowingBack.count.grouped,
                     label: "Non ti seguono indietro",
                     systemImage: "arrow.uturn.left",
                     tint: .orange)
            StatTile(value: result.fans.count.grouped,
                     label: "Ti seguono e non li segui",
                     systemImage: "heart.fill",
                     tint: .pink)
        }

        LazyVGrid(columns: columns, spacing: 12) {
            StatTile(value: percent(result.reciprocityRate),
                     label: "Reciprocità sui seguiti",
                     systemImage: "arrow.left.arrow.right",
                     tint: .teal)
            StatTile(value: ratio(result.followerToFollowingRatio),
                     label: "Rapporto follower / seguiti",
                     systemImage: "scalemass",
                     tint: .indigo)
        }

        if let diff = state.latestDiff, diff.previous.id != diff.current.id {
            changeCard(diff)
        }

        growthCard()

        NavigationLink {
            ActivityView(embedded: true)
        } label: {
            Card {
                HStack {
                    Label("Attività e abitudini", systemImage: "waveform.path.ecg")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)

        if !result.warnings.isEmpty {
            Card(title: "Da sapere") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(result.warnings.enumerated()), id: \.offset) { item in
                        Label(item.element, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func changeCard(_ diff: SnapshotDiff) -> some View {
        Card(title: "Dall'import precedente",
             footnote: "Confronto con lo snapshot del " + diff.previous.createdAt.formatted(date: .abbreviated, time: .shortened)) {
            HStack(spacing: 16) {
                deltaColumn(value: diff.gainedFollowers.count,
                            label: "Nuovi follower",
                            tint: .green,
                            symbol: "arrow.up.right")
                Divider()
                deltaColumn(value: diff.lostFollowers.count,
                            label: "Follower persi",
                            tint: .red,
                            symbol: "arrow.down.right")
                Divider()
                deltaColumn(value: diff.netFollowers,
                            label: "Saldo",
                            tint: diff.netFollowers >= 0 ? .green : .red,
                            symbol: "equal")
            }

            if !diff.lostFollowers.isEmpty {
                NavigationLink {
                    AccountListScreen(title: "Follower persi",
                                      explanation: "Erano nello snapshot precedente e non sono più nell'ultimo.",
                                      accounts: diff.lostFollowers.map { Account(username: $0) })
                } label: {
                    Label("Vedi chi se n'è andato", systemImage: "chevron.right.circle")
                        .font(.footnote.weight(.medium))
                }
            }
        }
    }

    private func deltaColumn(value: Int, label: String, tint: Color, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value > 0 && symbol == "equal" ? "+\(value)" : "\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func growthCard() -> some View {
        let series = state.followerSeries
        if series.count > 1 {
            Card(title: "Crescita follower",
                 footnote: state.followerSeriesIsFromSnapshots
                    ? "Ricostruita dagli snapshot salvati su questo telefono."
                    : "Ricostruita dalle date di inizio follow contenute nell'export.") {
                Chart(series) { bucket in
                    AreaMark(x: .value("Mese", bucket.date),
                             y: .value("Follower", bucket.count))
                    .foregroundStyle(
                        LinearGradient(colors: [Color.accentColor.opacity(0.35), .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    LineMark(x: .value("Mese", bucket.date),
                             y: .value("Follower", bucket.count))
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 190)
            }
        }
    }

    // MARK: - API

    @ViewBuilder
    private func apiSummary() -> some View {
        if let profile = state.graphProfile {
            Card(title: "Account collegato",
                 footnote: "Dati dall'API ufficiale. Le liste di follower non sono esposte da Instagram a nessuna app.") {
                VStack(alignment: .leading, spacing: 10) {
                    if let username = profile.username {
                        Text("@" + username).font(.title3.weight(.semibold))
                    }
                    HStack(spacing: 20) {
                        metric(profile.followersCount, "Follower")
                        metric(profile.followsCount, "Seguiti")
                        metric(profile.mediaCount, "Contenuti")
                    }
                }
            }

            if !state.graphInsights.isEmpty {
                Card(title: "Ultimi 28 giorni") {
                    VStack(spacing: 10) {
                        ForEach(state.graphInsights, id: \.name) { insight in
                            HStack {
                                Text(insight.title)
                                    .font(.subheadline)
                                Spacer()
                                Text(insight.total.grouped)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }

            if !state.graphMedia.isEmpty {
                topPostsCard()
            }
        }
    }

    @ViewBuilder
    private func topPostsCard() -> some View {
        let top = state.graphMedia
            .sorted { $0.engagement > $1.engagement }
            .prefix(5)

        Card(title: "Contenuti con più interazioni") {
            VStack(spacing: 12) {
                ForEach(Array(top)) { media in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(caption(for: media))
                                .font(.subheadline)
                                .lineLimit(2)
                            if let date = media.date {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Label("\(media.likeCount ?? 0)", systemImage: "heart")
                                .font(.caption).monospacedDigit()
                            Label("\(media.commentsCount ?? 0)", systemImage: "bubble.right")
                                .font(.caption).monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func caption(for media: GraphMedia) -> String {
        let text = (media.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? (media.mediaType ?? "Contenuto") : text
    }

    private func metric(_ value: Int?, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map { $0.grouped } ?? "–")
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func percent(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        return String(format: "%.0f%%", value * 100)
    }

    private func ratio(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "–" }
        return String(format: "%.2f", value)
    }
}
